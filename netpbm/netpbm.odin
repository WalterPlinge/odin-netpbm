/*
	TODO
		LEGACY
			[ ] not implemented
			[-] implemented partially
			[x] implemented
			[?] optional / considering
			[!] requires rework
	[-] formats
		[-] PNM
			[-] PBM (P1, P4)
				[x] header
				[ ] raster
					[ ] binary
					[ ] ascii
			[-] PGM (P2, P5)
				[x] header
				[ ] raster
					[ ] binary
					[ ] ascii
			[-] PPM (P3, P6)
				[x] header
				[ ] raster
					[ ] binary
					[ ] ascii
		[-] PAM (P7)
			[-] header
			[ ] raster
		[ ] PFM (Pf, PF)
			[ ] header
			[ ] raster
	[-] misc. specification
		[x] comments (PNM headers)
		[-] maxval
			[-] 1 byte values
			[-] 2 byte values
			[ ] arbitrary maxvals (options and metadata)
			[?] endian conversion or info flag
		[!] multiple images
		[?] Gamma correction, is it necessary?
	[-] reading
		[!] memory
		[!] file
		[?] stream/context
	[-] writing
		[!] memory
		[!] file
		[?] stream/context
	[-] use allocators
	[-] proper errors
	[!] pass options
	[!] use core:image.Image.metadata
*/
package netpbm

import "core:bytes"
import "core:fmt"
import "core:image"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode"



Image :: image.Image

Format :: enum {
	P1, P2, P3, P4, P5, P6, P7, Pf, PF,
}

Header :: struct {
	format:       Format,
	width:        int,
	height:       int,
	maxval:       int, // P2, P3, P5, P6, P7
	depth:        int, // P7
	tupltype:     string, // P7
	scale:        f32, // Pf, PF
	total_bytes:  int,
}

Error :: enum {
	None = 0,

	// reading
	File_Not_Readable,
	Invalid_Signature,
	Invalid_Character_In_Header_Token,
	Incomplete_Header,
	Invalid_Width,
	Invalid_Height,
	Invalid_Maxval,
	Invalid_Depth,

	// writing
	File_Not_Writable,
	Invalid_Channel_Count,
	Invalid_Image_Depth,
	Invalid_Image_Info,
	Empty_List,
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



write :: proc {
	write_to_file,
	write_to_buffer,
	write_multiple_to_file,
	write_multiple_to_buffer,
}

write_to_file :: proc(filename: string, image: Image, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator

	data: []byte; defer delete(data)
	data = write_to_buffer(image) or_return

	if !os.write_entire_file(filename, data) {
		return .File_Not_Writable
	}

	return
}

write_to_buffer :: proc(image: Image, allocator := context.allocator) -> (data: []byte, err: Error) {
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
	header := fmt.tprintf("%s\n%v %v\n%v\n", "P6", image.width, image.height, maxval)

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

write_multiple_to_file :: proc(filename: string, images: []Image, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator

	data, error := write_multiple_to_buffer(images); defer delete(data)
	if error != .None {
		return error
	}

	if !os.write_entire_file(filename, data[:]) {
		return .File_Not_Writable
	}

	return
}

write_multiple_to_buffer :: proc(images: []Image, allocator := context.allocator) -> (data: [dynamic]byte, err: Error) {
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
		d := write_to_buffer(img) or_return
		append(&data, ..d)
	}

	return
}



read :: proc {
	read_from_file,
	read_from_buffer,
}

read_from_file :: proc(filename: string, allocator := context.allocator) -> (images: [dynamic]Image, err: Error) {
	context.allocator = allocator

	data, ok := os.read_entire_file(filename); defer delete(data)
	if !ok {
		return nil, .File_Not_Readable
	}

	return read_from_buffer(data)
}

read_from_buffer :: proc(data: []byte, allocator := context.allocator) -> (images: [dynamic]Image, err: Error) {
	context.allocator = allocator

	// we should have at least one
	reserve(&images, 1)
	remaining_data := data

	// while we still have data
	for len(remaining_data) > 0 {
		header := parse_header(remaining_data) or_return
		using header

		// pixel_length is calculated, so could be more than we have if payload is corrupt
		// if len(remaining_data) < pixel_start + pixel_length {
		// 	return images, .Invalid_Buffer_Size
		// }

		// pixel_data    := remaining_data[pixel_start:][:pixel_length]
		// remaining_data = remaining_data[pixel_start + pixel_length:]

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

		// bytes.buffer_init(&img.pixels, pixel_data)

		append(&images, img)
	}

	return images, Error.None
}



parse_header :: proc(data: []byte) -> (header: Header, err: Error) {
	/*
		P1, P4: width, height
		P2, P5: width, height, maxval (0 < n < 65536)
		P3, P6: width, height, maxval (0 < n < 65536)
		P7    : width, height, depth, maxval, tupltype
		Pf, PF: width, height, scale+endian
	*/

	// we need the signature and a space at least
	if len(data) < 3 {
		return header, .Incomplete_Header
	}

	if data[0] == 'P' {
		switch data[1] {
			case '1'..='6':
				return _parse_header_pnm(data)
			case '7':
				return _parse_header_pam(data)
			case 'F', 'f':
				return _parse_header_pfm(data)
		}
	}

	return header, .Invalid_Signature
}

@(private)
_parse_header_pnm :: proc(data: []byte) -> (header: Header, err: Error) {
	SIGNATURE_LENGTH :: 2
	header_formats := []Format{.P1, .P2, .P3, .P4, .P5, .P6,}
	header.format = header_formats[data[1] - '0' - 1]

	// have a list of fielda for easy iteration
	header_fields: []^int
	if header.format == .P1 || header.format == .P4 {
		header_fields = {&header.width, &header.height}
	} else {
		header_fields = {&header.width, &header.height, &header.maxval}
	}

	// loop state
	in_comment       := false
	already_in_space := true
	current_field    := 0
	current_value    := header_fields[0]

	parse_loop: for d, i in data[SIGNATURE_LENGTH:] {
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
			if current_field == len(header_fields) {
				header.total_bytes = i + SIGNATURE_LENGTH + 1
				break parse_loop
			}
			current_value = header_fields[current_field]
		} else {
			already_in_space = false

			if !unicode.is_digit(rune(d)) {
				return header, .Invalid_Character_In_Header_Token
			}

			//? could parse the digit in a better way
			val := int(d - '0')
			current_value^ = current_value^ * 10 + val
		}
	}

	// limit checking
	if current_field < len(header_fields) {
		return header, .Incomplete_Header
	}

	if header.width < 1 {
		return header, .Invalid_Width
	}

	if header.height < 1 {
		return header, .Invalid_Height
	}

	if header.format != .P1 && header.format != .P4 {
		if header.maxval < 1 || header.maxval > int(max(u16)) {
			return header, .Invalid_Maxval
		}
	}

	//? do we need to know the data start and end here,
	//? or just the header size and we can do other calculations later
	// #partial switch header.format {
	// 	case .P1:
	// 		total_pixels := height * width
	// 		for c, i in data[header.pixel_start:] {
	// 			if c == '0' || c == '1' {
	// 				total_pixels -= 1
	// 			}
	// 			if total_pixels == 0 {
	// 				header.pixel_length = i + 1
	// 				break
	// 			}
	// 		}
	// 		if total_pixels > 0 {
	// 			return header, .Invalid_Buffer_Size
	// 		}

	// 	case .P2:
	// 		payload := data[header.pixel_start:]
	// 		total_pixels := height * width
	// 		for c, i in payload {
	// 			if unicode.is_digit(rune(c)) \
	// 			&& (i + 1 == len(payload) || unicode.is_white_space(rune(payload[i + 1]))) {
	// 				total_pixels -= 1
	// 			}
	// 			if total_pixels == 0 {
	// 				header.pixel_length = i + 1
	// 				break
	// 			}
	// 		}
	// 		if total_pixels > 0 {
	// 			return header, .Invalid_Buffer_Size
	// 		}

	// 	case .P3:
	// 		payload := data[header.pixel_start:]
	// 		total_pixels := height * width * 3
	// 		for c, i in payload {
	// 			if unicode.is_digit(rune(c)) \
	// 			&& (i + 1 == len(payload) || unicode.is_white_space(rune(payload[i + 1]))) {
	// 				total_pixels -= 1
	// 			}
	// 			if total_pixels == 0 {
	// 				header.pixel_length = i + 1
	// 				break
	// 			}
	// 		}
	// 		if total_pixels > 0 {
	// 			return header, .Invalid_Buffer_Size
	// 		}

	// 	case .P4: header.pixel_length = height * ((width - 1) / 8 + 1)
	// 	case .P5: header.pixel_length = height * width * (2 if maxval > int(max(u8)) else 1)
	// 	case .P6: header.pixel_length = height * width * (2 if maxval > int(max(u8)) else 1) * 3
	// }

	// if header.pixel_start + header.pixel_length > len(data) {
	// 	return header, .Invalid_Buffer_Size
	// }

	return header, Error.None
}

@(private)
_parse_header_pam :: proc(data: []byte, allocator := context.allocator) -> (header: Header, err: Error) {
	context.allocator = allocator

	if string(data[0:3]) != "P7\n" {
		return header, .Invalid_Signature
	}
	header.format = .P7

	// this helps us move around the header
	SIGNATURE_LENGTH :: 3
	HEADER_END       :: "ENDHDR\n"

	// we can already work out the size of the header
	header_end_index := strings.index(string(data), HEADER_END)
	if header_end_index == -1 {
		return header, .Incomplete_Header
	}
	header.total_bytes = header_end_index + len(HEADER_END)

	// string buffer for the tupltype
	tupltype: strings.Builder
	strings.init_builder(&tupltype, context.temp_allocator); defer strings.destroy_builder(&tupltype)
	fmt.sbprint(&tupltype, "")

	// PAM uses actual lines, so we can iterate easily
	line_iterator := string(data[SIGNATURE_LENGTH : header_end_index])
	parse_loop: for line in strings.split_lines_iterator(&line_iterator) {
		line := line

		if len(line) == 0 || line[0] == '#' do continue

		token, _ := strings.fields_iterator(&line)

		switch token {
			case "WIDTH": header.width, _ = strconv.parse_int(strings.trim_space(line))
			case "HEIGHT": header.height, _ = strconv.parse_int(strings.trim_space(line))
			case "MAXVAL": header.maxval, _ = strconv.parse_int(strings.trim_space(line))
			case "DEPTH": header.depth, _ = strconv.parse_int(strings.trim_space(line))
			case "TUPLTYPE":
				if len(tupltype.buf) == 0 {
					fmt.sbprint(&tupltype, strings.trim_space(line))
				} else {
					fmt.sbprint(&tupltype, "", strings.trim_space(line))
				}
		}
	}

	if header.width < 1 {
		return header, .Invalid_Width
	}

	if header.height < 1 {
		return header, .Invalid_Height
	}

	if header.maxval < 1 {
		return header, .Invalid_Maxval
	}

	if header.depth < 1 {
		return header, .Invalid_Depth
	}

	header.tupltype = strings.clone(strings.to_string(tupltype), allocator)

	return header, Error.None
}

@(private)
_parse_header_pfm :: proc(data: []byte) -> (header: Header, err: Error) {
	// we can just cycle through tokens for PFM
	field_iterator := string(data)

	token, ok := strings.fields_iterator(&field_iterator)

	switch token {
		case "Pf": header.format = .Pf
		case "PF": header.format = .PF
		case: return header, .Invalid_Signature
	}

	token, ok = strings.fields_iterator(&field_iterator)
	if !ok do return header, .Incomplete_Header
	header.width, _ = strconv.parse_int(token)

	token, ok = strings.fields_iterator(&field_iterator)
	if !ok do return header, .Incomplete_Header
	header.height, _ = strconv.parse_int(token)

	token, ok = strings.fields_iterator(&field_iterator)
	if !ok do return header, .Incomplete_Header
	header.scale, _ = strconv.parse_f32(token)

	// pointer math to get header size
	header.total_bytes = int((uintptr(raw_data(field_iterator)) + 1) - uintptr(raw_data(data)))

	return header, Error.None
}



// @TODO: I don't know if this is necessary, there may be a built-in way to get this number
@(private)
BITS_PER_BYTE :: 8

@(private)
CHANNELS_PER_PIXEL :: 3

// Import Name        - snake_case (but prefer single word)
// Types              - Ada_Case
// Enum Values        - Ada_Case
// Procedures         - snake_case
// Local Variables    - snake_case
// Constant Variables - SCREAMING_SNAKE_CASE
