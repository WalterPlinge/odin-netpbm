/*
	TODO
		LEGACY
			[ ] not implemented
			[-] implemented partially
			[x] implemented
			[?] optional / considering
			[!] requires rework
	[x] formats
		[x] PNM
			[x] PBM (P1, P4)
				[x] header
				[x] raster
					[x] binary
					[x] ascii
			[x] PGM (P2, P5)
				[x] header
				[x] raster
					[x] binary
					[x] ascii
			[x] PPM (P3, P6)
				[x] header
				[x] raster
					[x] binary
					[x] ascii
		[x] PAM (P7)
			[x] header
				[x] error on duplicate fields (apart from tupltype)
			[x] raster
		[x] PFM (Pf, PF)
			[x] header
			[x] raster
	[-] misc. specification
		[x] comments (PNM headers)
		[x] maxval
			[x] 1 byte values
			[x] 2 byte values
			[x] arbitrary maxvals (options and metadata)
		[ ] multiple images
	[-] reading
		[x] memory
		[x] file
		[ ] stream/context
	[-] writing
		[x] memory
		[x] file
		[ ] stream/context
	[x] use allocators
	[-] proper errors
	[-] pass options
	[!] use core:image.Image.metadata
*/

/*
? should we have a function that will generate an appropriate header from an image
? write_to_buffer:
	should we have checks for everything (PBM needs 1 channel, PPM needs 3 etc)
	or will we leave it the caller's responsibility
	or will we provide a helper function that suggests a format for the image
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

Formats :: bit_set[Format]
PBM :: Formats{.P1, .P4}
PGM :: Formats{.P2, .P5}
PPM :: Formats{.P3, .P6}
PNM :: PBM + PGM + PPM
PAM :: Formats{.P7}
PFM :: Formats{.Pf, .PF}
ASCII :: Formats{.P1, .P2, .P3}
BINARY :: Formats{.P4, .P5, .P6} + PAM + PFM



// P1, P4: width, height
// P2, P5: width, height, maxval
// P3, P6: width, height, maxval
// P7    : width, height, maxval, depth (channels), tupltype
// Pf, PF: width, height, scale+endian

// Some aesthetic differences from the specifications:
// `channels` is for the PAM specification `depth`
// `depth` is instead to know how many bytes will fit `maxval` (consistent with `core:image`)
// `scale` and `endianness` are separated, so `scale` will always be positive
// `endianness` will only be `Little` for a negative `scale` PFM
// `endianness` only describes the netpbm data, the image buffer will be native
Header :: struct {
	format:     Format,
	width:      int,
	height:     int,
	channels:   int,
	depth:      int,
	maxval:     int,
	tupltype:   string,
	scale:      f32,
	endianness: enum{ Big, Little },
}

Error :: enum {
	None = 0,

	// reading
	File_Not_Readable,
	Invalid_Signature,
	Invalid_Header_Token_Character,
	Incomplete_Header,
	Invalid_Header_Value,
	Duplicate_Header_Field,
	Buffer_Too_Small,
	Invalid_Buffer_ASCII_Token,
	Invalid_Buffer_Value,

	// writing
	File_Not_Writable,
	Invalid_Format,
	Invalid_Image_Depth,
}



delete_header :: proc(using header: ^Header) {
	if format == .P7 {
		delete(tupltype)
		tupltype = ""
	}
}


// Reading NetPBM files currently does not support multiple images in binary files
read :: proc {
	read_from_file,
	read_from_buffer,
}

read_from_file :: proc(filename: string, allocator := context.allocator) -> (img: Image, err: Error) {
	context.allocator = allocator

	data, ok := os.read_entire_file(filename); defer delete(data)
	if !ok {
		err = .File_Not_Readable
		return
	}

	return read_from_buffer(data)
}

read_from_buffer :: proc(data: []byte, allocator := context.allocator) -> (img: Image, err: Error) {
	context.allocator = allocator

	hdr: Header; defer delete_header(&hdr)
	hdr_size: int
	hdr, hdr_size = parse_header(data) or_return

	img_data := data[hdr_size:]
	img = decode_image(hdr, img_data) or_return

	//! needs an info struct
	new_hdr := new(Header)
	new_hdr^ = hdr
	if hdr.tupltype != "" {
		new_hdr.tupltype = strings.clone(hdr.tupltype)
	}
	img.metadata = cast(^image.PNG_Info) new_hdr

	return img, Error.None
}



write :: proc {
	write_to_file,
	write_to_buffer,
}

write_to_file :: proc(filename: string, img: Image, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator

	data: []byte; defer delete(data)
	data = write_to_buffer(img) or_return

	if ok := os.write_entire_file(filename, data); !ok {
		return .File_Not_Writable
	}

	return Error.None
}

write_to_buffer :: proc(img: Image, allocator := context.allocator) -> (buffer: []byte, err: Error) {
	context.allocator = allocator

	hdr := cast(^Header) img.metadata.(^image.PNG_Info)

	data: strings.Builder
	strings.init_builder(&data)

	// all PNM headers start with the format
	fmt.sbprintf(&data, "%s\n", hdr.format)
	if hdr.format in PNM {
		fmt.sbprintf(&data, "%i %i\n", img.width, img.height)
		if hdr.format not_in PBM {
			fmt.sbprintf(&data, "%i\n", hdr.maxval)
		}
	} else if hdr.format in PAM {
		fmt.sbprintf(&data, "WIDTH %i\nHEIGHT %i\nMAXVAL %i\nDEPTH %i\nTUPLTYPE %s\nENDHDR\n",
			img.width, img.height, hdr.maxval, img.channels, hdr.tupltype)
	} else if hdr.format in PFM {
		scale := hdr.scale if hdr.endianness == .Big else -hdr.scale
		fmt.sbprintf(&data, "%i %i\n%f\n", img.width, img.height, scale)
	}

	switch hdr.format {
	// Compressed binary
	case .P4:
		pixels := img.pixels.buf[:]
		for y in 0 ..< img.height {
			i := y
			b: byte
			for x in 0 ..< img.width {
				i := i * img.width + x
				bit := byte(7 - (x % 8))
				v : byte = 0 if pixels[i] == 0 else 1
				b |= (v << bit)

				if bit == 0 {
					resize(&data.buf, len(data.buf) + 1)
					data.buf[len(data.buf) - 1] = b
					b = 0
				}
			}

			if b != 0 {
				resize(&data.buf, len(data.buf) + 1)
				data.buf[len(data.buf) - 1] = b
				b = 0
			}
		}

	// Simple binary
	case .P5, .P6, .P7, .Pf, .PF:
		header := data.buf[:]
		pixels := img.pixels.buf[:]
		resize(&data.buf, len(data.buf) + len(pixels))
		mem.copy(raw_data(data.buf[len(header):]), raw_data(pixels), len(pixels))

		// convert from native endianness
		if img.depth == 2 {
			pixels := mem.slice_data_cast([]u16be, data.buf[len(header):])
			for p in &pixels {
				p = u16be(transmute(u16) p)
			}
		} else if hdr.format in PFM {
			if hdr.endianness == .Big {
				pixels := mem.slice_data_cast([]f32be, data.buf[len(header):])
				for p in &pixels {
					p = f32be(transmute(f32) p)
				}
			} else {
				pixels := mem.slice_data_cast([]f32le, data.buf[len(header):])
				for p in &pixels {
					p = f32le(transmute(f32) p)
				}
			}
		}

	// If-it-looks-like-a-bitmap ASCII
	case .P1:
		pixels := img.pixels.buf[:]
		for y in 0 ..< img.height {
			i := y
			for x in 0 ..< img.width {
				i := i * img.width + x
				fmt.sbprintf(&data, "%c", byte('0') if pixels[i] == 0 else byte('1'))
			}
			fmt.sbprint(&data, "\n")
		}

	// Token ASCII
	case .P2, .P3:
		switch img.depth {
		case 1:
			pixels := img.pixels.buf[:]
			for y in 0 ..< img.height {
				i := y
				for x in 0 ..< img.width {
					i := i * img.width + x
					for c in 0 ..< img.channels {
						i := i * img.channels + c
						fmt.sbprintf(&data, "%i ", pixels[i])
					}
				}
				fmt.sbprint(&data, "\n")
			}

		case 2:
			pixels := mem.slice_data_cast([]u16, img.pixels.buf[:])
			for y in 0 ..< img.height {
				i := y
				for x in 0 ..< img.width {
					i := i * img.width + x
					for c in 0 ..< img.channels {
						i := i * img.channels + c
						fmt.sbprintf(&data, "%i ", pixels[i])
					}
				}
				fmt.sbprint(&data, "\n")
			}

		case:
			return data.buf[:], .Invalid_Image_Depth
		}

	case:
		return data.buf[:], .Invalid_Format
	}

	return data.buf[:], Error.None
}



parse_header :: proc(data: []byte, allocator := context.allocator) -> (hdr: Header, length: int, err: Error) {
	context.allocator = allocator

	// we need the signature and a space
	if len(data) < 3 {
		err = .Incomplete_Header
		return
	}

	if data[0] == 'P' {
		switch data[1] {
		case '1' ..= '6':
			return _parse_header_pnm(data)
		case '7':
			return _parse_header_pam(data, allocator)
		case 'F', 'f':
			return _parse_header_pfm(data)
		}
	}

	err = .Invalid_Signature
	return
}

@(private)
_parse_header_pnm :: proc(data: []byte) -> (hdr: Header, length: int, err: Error) {
	SIG_LENGTH :: 2

	{
		header_formats := []Format{.P1, .P2, .P3, .P4, .P5, .P6}
		hdr.format = header_formats[data[1] - '0' - 1]
	}

	// have a list of fielda for easy iteration
	header_fields: []^int
	if hdr.format in PBM {
		header_fields = {&hdr.width, &hdr.height}
		hdr.maxval = 1 // we know maxval for a bitmap
	} else {
		header_fields = {&hdr.width, &hdr.height, &hdr.maxval}
	}

	// loop state
	in_comment := false
	already_in_space := true
	current_field := 0
	current_value := header_fields[0]
	length = SIG_LENGTH

	parse_loop: for d, i in data[SIG_LENGTH:] {
		length += 1

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
				// length is 1-index so we'll increment again
				length += 1
				break parse_loop
			}
			current_value = header_fields[current_field]
		} else {
			already_in_space = false

			if !unicode.is_digit(rune(d)) {
				err = .Invalid_Header_Token_Character
				return
			}

			val := int(d - '0')
			current_value^ = current_value^ * 10 + val
		}
	}

	// set extra info
	hdr.channels = 3 if hdr.format in PPM else 1
	hdr.depth = 2 if hdr.maxval > int(max(u8)) else 1

	// limit checking
	if current_field < len(header_fields) {
		err = .Incomplete_Header
		return
	}

	if hdr.width < 1 \
	|| hdr.height < 1 \
	|| hdr.maxval < 1 || hdr.maxval > int(max(u16)) {
		err = .Invalid_Header_Value
		return
	}

	return
}

@(private)
_parse_header_pam :: proc(data: []byte, allocator := context.allocator) -> (hdr: Header, length: int, err: Error) {
	context.allocator = allocator

	// the spec needs the newline
	if string(data[0:3]) != "P7\n" {
		err = .Invalid_Signature
		return
	}
	hdr.format = .P7

	SIGNATURE_LENGTH :: 3
	HEADER_END :: "ENDHDR\n"

	// we can already work out the size of the header
	header_end_index := strings.index(string(data), HEADER_END)
	if header_end_index == -1 {
		err = .Incomplete_Header
		return
	}
	length = header_end_index + len(HEADER_END)

	// string buffer for the tupltype
	tupltype: strings.Builder
	strings.init_builder(&tupltype, context.temp_allocator); defer strings.destroy_builder(&tupltype)
	fmt.sbprint(&tupltype, "")

	// PAM uses actual lines, so we can iterate easily
	line_iterator := string(data[SIGNATURE_LENGTH : header_end_index])
	parse_loop: for line in strings.split_lines_iterator(&line_iterator) {
		line := line

		if len(line) == 0 || line[0] == '#' {
			continue
		}

		field, ok := strings.fields_iterator(&line)
		value := strings.trim_space(line)

		// the field will change, but the logic stays the same
		current_field: ^int

		switch field {
		case "WIDTH":  current_field = &hdr.width
		case "HEIGHT": current_field = &hdr.height
		case "DEPTH":  current_field = &hdr.channels
		case "MAXVAL": current_field = &hdr.maxval

		case "TUPLTYPE":
			if len(value) == 0 {
				err = .Invalid_Header_Value
				return
			}

			if len(tupltype.buf) == 0 {
				fmt.sbprint(&tupltype, value)
			} else {
				fmt.sbprint(&tupltype, "", value)
			}

			continue

		case:
			continue
		}

		if current_field^ != 0 {
			err = .Duplicate_Header_Field
			return
		}
		current_field^, ok = strconv.parse_int(value)
		if !ok {
			err = .Invalid_Header_Value
			return
		}
	}

	// extra info
	hdr.depth = 2 if hdr.maxval > int(max(u8)) else 1

	// limit checking
	if hdr.width < 1 \
	|| hdr.height < 1 \
	|| hdr.depth < 1 \
	|| hdr.maxval < 1 \
	|| hdr.maxval > int(max(u16)) {
		err = .Invalid_Header_Value
		return
	}

	hdr.tupltype = strings.clone(strings.to_string(tupltype))
	return
}

@(private)
_parse_header_pfm :: proc(data: []byte) -> (hdr: Header, length: int, err: Error) {
	// we can just cycle through tokens for PFM
	field_iterator := string(data)
	field, ok := strings.fields_iterator(&field_iterator)

	switch field {
	case "Pf":
		hdr.format = .Pf
		hdr.channels = 1
	case "PF":
		hdr.format = .PF
		hdr.channels = 3
	case:
		err = .Invalid_Signature
		return
	}

	// floating point
	hdr.depth = 4

	// width
	field, ok = strings.fields_iterator(&field_iterator)
	if !ok {
		err = .Incomplete_Header
		return
	}
	hdr.width, ok = strconv.parse_int(field)
	if !ok {
		err = .Invalid_Header_Value
		return
	}

	// height
	field, ok = strings.fields_iterator(&field_iterator)
	if !ok {
		err = .Incomplete_Header
		return
	}
	hdr.height, ok = strconv.parse_int(field)
	if !ok {
		err = .Invalid_Header_Value
		return
	}

	// scale (sign is endianness)
	field, ok = strings.fields_iterator(&field_iterator)
	if !ok {
		err = .Incomplete_Header
		return
	}
	hdr.scale, ok = strconv.parse_f32(field)
	if !ok {
		err = .Invalid_Header_Value
		return
	}

	if hdr.scale < 0.0 {
		hdr.endianness = .Little
		hdr.scale = -hdr.scale
	}

	// pointer math to get header size
	length = int((uintptr(raw_data(field_iterator)) + 1) - uintptr(raw_data(data)))

	// limit checking
	if hdr.width < 1 \
	|| hdr.height < 1 \
	|| hdr.scale == 0.0 {
		err = .Invalid_Header_Value
		return
	}

	return
}



decode_image :: proc(header: Header, data: []byte, allocator := context.allocator) -> (img: Image, err: Error) {
	context.allocator = allocator

	img = Image {
		width    = header.width,
		height   = header.height,
		channels = header.channels,
		depth    = header.depth,
	}

	buffer_size := img.width * img.height * img.channels * img.depth

	// we can check data size for binary formats
	if header.format in BINARY {
		if header.format == .P4 {
			p4_size := (img.width / 8 + 1) * img.height
			if len(data) < p4_size {
				return img, .Buffer_Too_Small
			}
		} else {
			if len(data) < buffer_size {
				return img, .Buffer_Too_Small
			}
		}
	}

	// for ASCII and P4, we use length for the termination condition, so start at 0
	// BINARY will be a simple memcopy so the buffer length should also be initialised
	if header.format in ASCII || header.format == .P4 {
		bytes.buffer_init_allocator(&img.pixels, 0, buffer_size)
	} else {
		bytes.buffer_init_allocator(&img.pixels, buffer_size, buffer_size)
	}

	switch header.format {
	// Compressed binary
	case .P4:
		for d in data {
			for b in 1 ..= 8 {
				bit := byte(8 - b)
				pix := (d & (1 << bit)) >> bit
				bytes.buffer_write_byte(&img.pixels, pix)
				if len(img.pixels.buf) % img.width == 0 {
					break
				}
			}

			if len(img.pixels.buf) == cap(img.pixels.buf) {
				break
			}
		}

	// Simple binary
	case .P5, .P6, .P7, .Pf, .PF:
		mem.copy(raw_data(img.pixels.buf), raw_data(data), buffer_size)

		// convert to native endianness
		if header.format in PFM {
			pixels := mem.slice_data_cast([]f32, img.pixels.buf[:])
			if header.endianness == .Little {
				for p in &pixels {
					p = f32(transmute(f32le) p)
				}
			} else {
				for p in &pixels {
					p = f32(transmute(f32be) p)
				}
			}
		} else {
			if img.depth == 2 {
				pixels := mem.slice_data_cast([]u16, img.pixels.buf[:])
				for p in &pixels {
					p = u16(transmute(u16be) p)
				}
			}
		}

	// If-it-looks-like-a-bitmap ASCII
	case .P1:
		for c in data {
			switch c {
			case '0', '1':
				bytes.buffer_write_byte(&img.pixels, c - '0')
			}

			if len(img.pixels.buf) == cap(img.pixels.buf) {
				break
			}
		}

		if len(img.pixels.buf) < cap(img.pixels.buf) {
			err = .Buffer_Too_Small
			return
		}

	// Token ASCII
	case .P2, .P3:
		field_iterator := string(data)
		for field in strings.fields_iterator(&field_iterator) {
			value, ok := strconv.parse_int(field)
			if !ok {
				err = .Invalid_Buffer_ASCII_Token
				return
			}

			//? do we want to enforce the maxval, the limit, or neither
			if value > int(max(u16)) /*header.maxval*/ {
				err = .Invalid_Buffer_Value
				return
			}

			switch img.depth {
			case 1:
				bytes.buffer_write_byte(&img.pixels, u8(value))
			case 2:
				vb := transmute([2]u8) u16(value)
				bytes.buffer_write(&img.pixels, vb[:])
			}

			if len(img.pixels.buf) == cap(img.pixels.buf) {
				break
			}
		}

		if len(img.pixels.buf) < cap(img.pixels.buf) {
			err = .Buffer_Too_Small
			return
		}
	}

	return
}



destroy_image :: proc(img: ^Image) {
	bytes.buffer_destroy(&img.pixels)
	header := transmute(^Header) img.metadata.(^image.PNG_Info)
	delete_header(header)
	free(header)
}
