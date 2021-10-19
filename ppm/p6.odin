// Import Name        - snake_case (but prefer single word)
// Types              - Ada_Case
// Enum Values        - Ada_Case
// Procedures         - snake_case
// Local Variables    - snake_case
// Constant Variables - SCREAMING_SNAKE_CASE

package image_ppm

/*
	TODO
	[-] specification
		[x] comments
		[-] maxval
			[x] 1 byte values
			[x] 2 byte values
			[ ] arbitrary maxvals (options and metadata)
			[?] endian conversion or info flag
		[-] multiple images
		[?] Gamma correction, is it necessary?
	[-] reading
		[x] memory
		[x] file
		[?] stream/context
	[-] writing
		[x] memory
		[x] file
		[?] stream/context
	[x] use allocators
	[-] proper errors
	[ ] pass options
	[ ] use core:image.Image.metadata
	[ ] ascii version (P3)
	[ ] PGM (P5, P2)
	[ ] PBM (P4, P1)
	[ ] PAM (P7)
	[ ] PFM (Pf, PF)
*/

import "core:bytes"
import "core:fmt"
import "core:image"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:unicode"





SIGNATURE :: "P6"





Image :: image.Image

Error :: enum {
	None = 0,
	// loading
	File_Not_Readable,
	Invalid_PPM_Signature,
	Invalid_Header_Value,
	Invalid_Header,
	Invalid_Maxval,
	Invalid_Buffer_Size,
	// saving
	File_Not_Writable,
	Invalid_Image_Depth,
	Invalid_Channel_Count,
}

Header :: struct {
	//ascii: bool,
	width: int,
	height: int,
	maxval: int,
	pixel_start: int,
	pixel_length: int,
}





destroy :: proc(images: [dynamic]Image) {
	images := images
	if images == nil {
		return
	}
	for i in &images {
		bytes.buffer_destroy(&i.pixels)
	}
	delete(images)
}

read :: proc(data: []byte, allocator := context.allocator) -> (images: [dynamic]Image, err: Error) {
	context.allocator = allocator

	reserve(&images, 1)
	remaining_data := data

	for len(remaining_data) > 0 {
		header := read_header(remaining_data) or_return
		using header

		if len(remaining_data) < pixel_start + pixel_length {
			return images, Error.Invalid_Buffer_Size
		}

		pixel_data := remaining_data[pixel_start:][:pixel_length]
		remaining_data = remaining_data[pixel_start + pixel_length:]

		bytes_per_channel := maxval > int(max(u8)) \
			? size_of(u16) \
			: size_of(u8 )

		img := Image{}
		img.width = width
		img.height = height
		img.channels = CHANNELS_PER_PIXEL
		img.depth = bytes_per_channel * BITS_PER_BYTE

		bytes.buffer_init(&img.pixels, pixel_data)

		// @TODO: do I need to care about endianness? i.e. change the pixel data from u16be to u16?
		// PPM 2 byte format is big endian
		if bytes_per_channel == 2 {
			pixels := mem.slice_data_cast([]u16, img.pixels.buf[:])
			for p in &pixels {
				p = u16(transmute(u16be) p)
			}
		}

		append(&images, img)
	}

	return images, Error.None
}

write :: proc(img: Image, allocator := context.allocator) -> (data: []byte, err: Error) {
	context.allocator = allocator

	if img.channels != CHANNELS_PER_PIXEL {
		return nil, Error.Invalid_Channel_Count
	}

	if img.depth != size_of(u8 ) * BITS_PER_BYTE \
	&& img.depth != size_of(u16) * BITS_PER_BYTE {
		return nil, Error.Invalid_Image_Depth
	}
	// @TODO: max_val should come from an options struct
	max_val := img.depth == BITS_PER_BYTE ? int(max(u8)) : int(max(u16))

	// format header string
	header := fmt.tprintf("%s %v %v %v\n", SIGNATURE, img.width, img.height, max_val)

	// Calculate capacity
	bytes_per_channel := img.depth / BITS_PER_BYTE
	// @TODO: overflow protection
	capacity := len(header) + img.width * img.height * img.channels * bytes_per_channel

	data = make([]byte, capacity)

	copy(data[:], header)
	// @TODO: make sure img.pixels is valid FORMAT and SIZE
	pixel_data := data[len(header):]
	copy(pixel_data[:], img.pixels.buf[:])

	// PPM 2 byte format is big endian
	if bytes_per_channel == 2 {
		pixels := mem.slice_data_cast([]u16be, pixel_data)
		for p in &pixels {
			p = u16be(transmute(u16) p)
		}
	}

	return
}



read_from_file :: proc(filename: string, allocator := context.allocator) -> (images: [dynamic]Image, err: Error) {
	context.allocator = allocator

	data, ok := os.read_entire_file(filename)
	defer delete(data)

	if !ok {
		return nil, .File_Not_Readable
	}

	return read(data)
}

write_to_file :: proc(filename: string, img: Image, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator

	data, error := write(img)
	defer delete(data)
	if error != .None {
		return error
	}

	if !os.write_entire_file(filename, data) {
		return .File_Not_Writable
	}

	return
}





valid_signature :: proc(data: []byte) -> bool {
	return string(data[:len(SIGNATURE)]) == SIGNATURE
}

read_header :: proc(data: []byte) -> (header: Header, err: Error) {
	if !valid_signature(data) {
		return header, .Invalid_PPM_Signature
	}

	// fields
	width, height, maxval: int
	header_fields := []^int{ &width, &height, &maxval }

	// states
	in_comment := false
	already_in_space := true
	current_field := 0
	current_value := header_fields[0]

	// @FIXME: change loop to index-for, to more correctly parse the integers
	loop:
	for d, i in data[len(SIGNATURE):] {
		// handle comments
		if in_comment {
			switch d {
				// comments only go up to next carriage return or line feed
				case '\r', '\n':
					in_comment = false
			}
			continue
		} else if d == '#' {
			in_comment = true
			continue
		}

		// handle whitespace
		in_space := unicode.is_white_space(rune(d))
		if in_space {
			// still in space
			if already_in_space {
				continue
			}
			already_in_space = true

			// switch to next value
			current_field += 1
			if current_field >= len(header_fields) {
				header.pixel_start = i + len(SIGNATURE) + 1
				break loop
			}
			current_value = header_fields[current_field]
		} else {
			already_in_space = false

			if !unicode.is_digit(rune(d)) {
				return header, .Invalid_Header_Value
			}
			// @TODO: could parse the digit in a better way
			val, _ := strconv.parse_int(string([]byte{ d }))
			current_value^ = current_value^ * 10 + val
		}
	}

	if current_field < len(header_fields) {
		return header, .Invalid_Header
	}

	if maxval == 0 || maxval > int(max(u16)) {
		return header, .Invalid_Maxval
	}

	header.width = width
	header.height = height
	header.maxval = maxval
	header.pixel_length = width * height * CHANNELS_PER_PIXEL
	if maxval > int(max(u8)) {
		header.pixel_length *= size_of(u16)
	}

	return header, Error.None
}





// @TODO: there should be a builtin way to get this number
@(private)
BITS_PER_BYTE :: 8

@(private)
CHANNELS_PER_PIXEL :: 3
