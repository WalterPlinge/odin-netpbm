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
		[ ] multiple images
		[?] Gamma correction, is it necessary?
	[-] loading
		[x] memory
		[ ] file
		[?] stream
	[-] saving
		[x] memory
		[ ] file
		[?] stream
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
import "core:strconv"
import "core:unicode"





SIGNATURE :: "P6"





Image :: image.Image

Error :: enum {
	None = 0,
	// loading
	Invalid_PPM_Signature,
	Invalid_Header_Value,
	Invalid_Maxval,
	Invalid_Buffer_Size,
	// saving
	Invalid_Image_Depth,
	Invalid_Channel_Count,
}

Header :: struct {
	//ascii: bool,
	width: int,
	height: int,
	maxval: int,
	pixel_data: []byte,
}





load :: proc(data: []byte, allocator := context.allocator) -> (img: ^Image, err: Error) {
	context.allocator = allocator

	if img == nil {
		img = new(Image)
	}

	if !valid_signature(data) {
		return img, Error.Invalid_PPM_Signature
	}

	header := read_header(data) or_return
	using header

	img.width = width
	img.height = height
	img.channels = 3
	img.depth = maxval > int(max(u8))   \
		? size_of(u16) * BITS_PER_BYTE \
		: size_of(u8 ) * BITS_PER_BYTE
	bytes_per_channel := img.depth / BITS_PER_BYTE

	if len(pixel_data) < width * height * img.channels * bytes_per_channel {
		return img, Error.Invalid_Buffer_Size
	}

	bytes.buffer_init(&img.pixels, pixel_data)

	// @TODO: do I need to care about endianness? i.e. change the pixel data from u16be to u16?
	// PPM 2 byte format is big endian
	if bytes_per_channel == 2 {
		pixels := mem.slice_data_cast([]u16, img.pixels.buf[:])
		for p in &pixels {
			p = u16(transmute(u16be) p)
		}
	}

	return
}

when true {
save :: proc(img: ^Image, allocator := context.allocator) -> (data: []byte, err: Error) {
	context.allocator = allocator

	if img.channels != 3 {
		return {}, Error.Invalid_Channel_Count
	}

	if img.depth != 1 * BITS_PER_BYTE \
	&& img.depth != 2 * BITS_PER_BYTE {
		return {}, Error.Invalid_Image_Depth
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
}






valid_signature :: proc(data: []byte) -> bool {
	return string(data[:len(SIGNATURE)]) == SIGNATURE
}

read_header :: proc(data: []byte) -> (header: Header, err: Error) {
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
				header.pixel_data = data[i + len(SIGNATURE) + 1:]
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

	if maxval == 0 || maxval > int(max(u16)) {
		return header, .Invalid_Maxval
	}

	header.width = width
	header.height = height
	header.maxval = maxval

	return
}





// @TODO: there should be a builtin way to get this number
@(private)
BITS_PER_BYTE :: 8
