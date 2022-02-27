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
			[-] arbitrary maxvals (options and metadata)
			[?] endian conversion or info flag
		[x] multiple images
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
	[-] pass options
	[-] use core:image.Image.metadata
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
	// reading
	File_Not_Readable,
	Invalid_PPM_Signature,
	Invalid_Header_Value,
	Invalid_Header,
	Invalid_Maxval,
	Invalid_Buffer_Size,
	// writing
	File_Not_Writable,
	Invalid_Channel_Count,
	Invalid_Image_Depth,
	Invalid_Image_Info,
	Empty_List,
}

Header :: struct {
	// ascii:        bool,
	width:        int,
	height:       int,
	maxval:       int,
	pixel_start:  int,
	pixel_length: int,
}

Info :: struct {
	maxval: int,
	raw:    bool,
}



destroy :: proc(images: [dynamic]Image) {
	if images == nil {
		return
	}
	images := images
	for i in &images {
		bytes.buffer_destroy(&i.pixels)
		//if m, ok := i.metadata.(^PPM_Info); ok {
		//	free(m)
		//}
	}
	delete(images)
}

read :: proc(data: []byte, allocator := context.allocator) -> (images: [dynamic]Image, err: Error) {
	context.allocator = allocator

	// we should have at least one
	reserve(&images, 1)
	remaining_data := data

	// while we still have data
	for len(remaining_data) > 0 {
		header := read_header(remaining_data) or_return
		using header

		// pixel_length is calculated, so could be more than we have if payload is corrupt
		if len(remaining_data) < pixel_start + pixel_length {
			return images, .Invalid_Buffer_Size
		}

		pixel_data    := remaining_data[pixel_start:][:pixel_length]
		remaining_data = remaining_data[pixel_start + pixel_length:]

		bytes_per_channel := maxval > int(max(u8)) \
			? size_of(u16) \
			: size_of(u8 )

		img         := Image{}
		img.width    = width
		img.height   = height
		img.channels = CHANNELS_PER_PIXEL
		img.depth    = bytes_per_channel * BITS_PER_BYTE

		//info := new(PPM_Info)
		//info.maxval = maxval
		//img.metadata = info

		bytes.buffer_init(&img.pixels, pixel_data)

		append(&images, img)
	}

	return images, Error.None
}

write :: proc(image: Image, allocator := context.allocator) -> (data: []byte, err: Error) {
	context.allocator = allocator

	if image.channels != CHANNELS_PER_PIXEL {
		return nil, .Invalid_Channel_Count
	}

	if image.depth != size_of(u8 ) * BITS_PER_BYTE \
	&& image.depth != size_of(u16) * BITS_PER_BYTE {
		return nil, .Invalid_Image_Depth
	}

	// @TODO: maxval should probably come from an options struct
	maxval := image.depth == BITS_PER_BYTE \
		? int(max(u8 )) \
		: int(max(u16))
	//info, ok := image.metadata.(^PPM_Info)
	//if !ok {
	//	return nil, .Invalid_Image_Info
	//}
	//maxval := info.maxval

	// format header string
	header := fmt.tprintf("%s\n%v %v\n%v\n", SIGNATURE, image.width, image.height, maxval)

	// Calculate capacity
	bytes_per_channel := image.depth / BITS_PER_BYTE
	// @TODO: overflow protection ?
	capacity := len(header) + image.width * image.height * image.channels * bytes_per_channel

	data = make([]byte, capacity)

	copy(data[:], header)
	pixel_data := data[len(header):]
	// @TODO: make sure image.pixels is valid FORMAT and SIZE
	copy(pixel_data[:], image.pixels.buf[:])

	return
}

write_multiple :: proc(images: []Image, allocator := context.allocator) -> (data: [dynamic]byte, err: Error) {
	context.allocator = allocator

	// we can't write an empty list
	if images == nil {
		return nil, .Empty_List
	}
	images := images

	// just keep appending each image as written
	// calculating the size beforehand would either be too memory intensive or too clever for now
	data = make([dynamic]byte)
	for img in &images {
		d := write(img) or_return
		append(&data, ..d)
	}

	return
}



read_from_file :: proc(filename: string, allocator := context.allocator) -> (images: [dynamic]Image, err: Error) {
	context.allocator = allocator

	data, ok := os.read_entire_file(filename); defer delete(data)
	if !ok {
		return nil, .File_Not_Readable
	}

	return read(data)
}

write_to_file :: proc(filename: string, image: Image, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator

	data, error := write(image); defer delete(data)
	if error != .None {
		return error
	}

	if !os.write_entire_file(filename, data) {
		return .File_Not_Writable
	}

	return
}

write_multiple_to_file :: proc(filename: string, images: []Image, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator

	data, error := write_multiple(images); defer delete(data)
	if error != .None {
		return error
	}

	if !os.write_entire_file(filename, data[:]) {
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

	// have a list of fielda for easy iteration
	width, height, maxval: int
	header_fields := []^int{&width, &height, &maxval}

	// states
	in_comment       := false
	already_in_space := true
	current_field    := 0
	current_value    := header_fields[0]


	loop: for d, i in data[len(SIGNATURE):] {
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
			val := int('0' - d)
			// val, _ := strconv.parse_int(string([]byte{ d }))

			current_value^ = current_value^ * 10 + val
		}
	}

	if current_field < len(header_fields) {
		return header, .Invalid_Header
	}

	if maxval == 0 || maxval > int(max(u16)) {
		return header, .Invalid_Maxval
	}

	header.width        = width
	header.height       = height
	header.maxval       = maxval
	header.pixel_length = width * height * CHANNELS_PER_PIXEL
	if maxval > int(max(u8)) {
		header.pixel_length *= size_of(u16)
	}

	return header, Error.None
}



// @TODO: I don't know if this is necessary, but there may be a built-in way to get this number
@(private)
BITS_PER_BYTE :: 8

@(private)
CHANNELS_PER_PIXEL :: 3
