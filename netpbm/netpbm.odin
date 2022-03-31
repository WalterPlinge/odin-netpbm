/*
	TODO
		LEGACY
			[ ] not implemented
			[-] implemented partially
			[x] implemented
			[o] tested
			[?] optional / considering
			[!] requires rework
	[-] formats
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
		[-] PAM (P7)
			[-] header
				[?] error on duplicate fields (apart from tupltype)
			[x] raster
		[-] PFM (Pf, PF)
			[x] header
			[-] raster
				[?] raster rows are bottom to top, does that matter here?
	[-] misc. specification
		[x] comments (PNM headers)
		[x] maxval
			[x] 1 byte values
			[x] 2 byte values
			[x] arbitrary maxvals (options and metadata)
			[?] endian conversion or info flag
		[ ] multiple images
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
Formats :: bit_set[Format]

PBM :: Formats{.P1, .P4}
PGM :: Formats{.P2, .P5}
PPM :: Formats{.P3, .P6}
PNM :: PBM + PGM + PPM
PAM :: Formats{.P7}
PFM :: Formats{.Pf, .PF}
ASCII :: Formats{.P1, .P2, .P3}
BINARY :: Formats{.P4, .P5, .P6} + PAM + PFM

Endian :: enum {
	Big, Little,
}



// P1, P4: width, height
// P2, P5: width, height, maxval
// P3, P6: width, height, maxval
// P7    : width, height, maxval, depth (channels), tupltype
// Pf, PF: width, height, scale+endian

// Some aesthetic differences from the specifications:
// `channels` is for `depth` in PAM specification
// `depth` is instead to know how many bytes will fit `maxval` (consistent with `core:image`)
// `scale` and `endianness` are separated, so `scale` will always be positive
// `endianness` will only be `Little` for a negative `scale` PFM
// `endianness` only describes the netpbm data, the image buffer will be native
Header :: struct {
	format:      Format,
	width:       int,
	height:      int,
	channels:    int,
	depth:       int,
	maxval:      int,
	tupltype:    string,
	scale:       f32,
	endianness:  Endian,
	total_bytes: int,
}

Error :: enum {
	None = 0,

	// reading
	File_Not_Readable,
	Invalid_Signature,
	Invalid_Header_Token_Character,
	Incomplete_Header,
	Invalid_Width,
	Invalid_Height,
	Invalid_Maxval,
	Invalid_Channels_PAM_Depth,
	Invalid_Tupltype,
	Invalid_Scale,
	Buffer_Too_Small,
	Invalid_Buffer_ASCII_Token,
	Invalid_Buffer_Value,

	// writing
	File_Not_Writable,
	Invalid_Format,
	Invalid_Image_Channels,
	Invalid_Image_Depth,
}

// This will likely be in core:image
NetPBM_Info :: struct {
	format: Format,
	maxval: int,
	tupltype: string,
	scale: f32,
	endianness: Endian,
}



delete_header :: proc(using header: ^Header) {
	if format == .P7 {
		delete(tupltype)
		tupltype = ""
	}
}



read :: proc {
	read_from_file,
	read_from_buffer,
}

read_from_file :: proc(filename: string, allocator := context.allocator) -> (img: Image, err: Error) {
	context.allocator = allocator

	data, ok := os.read_entire_file(filename); defer delete(data)
	if !ok do return img, .File_Not_Readable

	return read_from_buffer(data)
}

read_from_buffer :: proc(data: []byte, allocator := context.allocator) -> (img: Image, err: Error) {
	context.allocator = allocator

	hdr: Header; defer delete_header(&hdr)
	hdr = parse_header(data) or_return

	img_data := data[hdr.total_bytes:]

	img = decode_image(hdr, img_data) or_return

	//! needs an info struct
	new_hdr := new(Header)
	new_hdr^ = hdr
	if hdr.tupltype != "" {
		new_hdr.tupltype = strings.clone(hdr.tupltype)
	}
	img.metadata = transmute(^image.PNG_Info) new_hdr

	return img, Error.None
}



write :: proc {
	write_to_file,
	write_to_buffer,
}

write_to_file :: proc(filename: string, img: Image, info: NetPBM_Info, allocator := context.allocator) -> (err: Error) {
	context.allocator = allocator

	data: []byte; defer delete(data)
	data = write_to_buffer(img, info) or_return

	if ok := os.write_entire_file(filename, data); !ok {
		return .File_Not_Writable
	}

	return Error.None
}

write_to_buffer :: proc(img: Image, info: NetPBM_Info, allocator := context.allocator) -> (buffer: []byte, err: Error) {
	context.allocator = allocator

	data: strings.Builder
	strings.init_builder(&data)

	// all PNM headers start the same
	fmt.sbprintf(&data, "%s\n", info.format)
	if info.format in PNM {
		fmt.sbprintf(&data, "%i %i\n", img.width, img.height)
		if info.format not_in PBM {
			fmt.sbprintf(&data, "%i\n", info.maxval)
		}
	} else if info.format in PAM {
		fmt.sbprintf(&data, "WIDTH %i\nHEIGHT %i\nMAXVAL %i\nDEPTH %i\nTUPLTYPE %s\nENDHDR\n",
			img.width, img.height, info.maxval, img.channels, info.tupltype)
	} else if info.format in PFM {
		scale := info.scale if info.endianness == .Big else -info.scale
		fmt.sbprintf(&data, "%i %i\n%f\n", img.width, img.height, scale)
	}

	//? should we have checks for everything (PBM needs 1 channel, PPM needs 3 etc)
	//? or will we leave it the caller's responsibility
	//? or will we provide a helper function that suggests a format for the image

	switch info.format {
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
		//! PFM rows are bottom to top, is that important for us or just the caller
		header := data.buf[:]
		pixels := img.pixels.buf[:]
		resize(&data.buf, len(data.buf) + len(pixels))
		mem.copy(raw_data(data.buf[len(header):]), raw_data(pixels), len(pixels))

		if img.depth == 2 {
			pixels := mem.slice_data_cast([]u16be, data.buf[len(header):])
			for p in &pixels {
				p = u16be(transmute(u16) p)
			}
		} else if info.format in PFM {
			if info.endianness == .Big {
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



parse_header :: proc(data: []byte, allocator := context.allocator) -> (header: Header, err: Error) {
	context.allocator = allocator

	// we need the signature and a space at least
	if len(data) < 3 {
		return header, .Incomplete_Header
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

	return header, .Invalid_Signature
}

@(private)
_parse_header_pnm :: proc(data: []byte) -> (header: Header, err: Error) {
	SIGNATURE_LENGTH :: 2

	{
		header_formats := []Format{.P1, .P2, .P3, .P4, .P5, .P6}
		header.format = header_formats[data[1] - '0' - 1]
	}

	// have a list of fielda for easy iteration
	header_fields: []^int
	if header.format in PBM {
		header_fields = {&header.width, &header.height}
		header.maxval = 1 // we know maxval for a bitmap
	} else {
		header_fields = {&header.width, &header.height, &header.maxval}
	}

	// loop state
	in_comment := false
	already_in_space := true
	current_field := 0
	current_value := header_fields[0]

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
				return header, .Invalid_Header_Token_Character
			}

			//? could parse the digit in a better way
			val := int(d - '0')
			current_value^ = current_value^ * 10 + val
		}
	}

	// set extra info
	header.channels = 3 if header.format in PPM else 1
	header.depth = 2 if header.maxval > int(max(u8)) else 1

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
	if header.maxval < 1 || header.maxval > int(max(u16)) {
		return header, .Invalid_Maxval
	}


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
	HEADER_END :: "ENDHDR\n"

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

		if len(line) == 0 || line[0] == '#' {
			continue
		}

		field, ok := strings.fields_iterator(&line)
		value := strings.trim_space(line)

		switch field {
		case "WIDTH":
			header.width, ok = strconv.parse_int(value)
			if !ok do return header, .Invalid_Width

		case "HEIGHT":
			header.height, ok = strconv.parse_int(value)
			if !ok do return header, .Invalid_Height

		case "DEPTH":
			header.channels, ok = strconv.parse_int(value)
			if !ok do return header, .Invalid_Channels_PAM_Depth

		case "MAXVAL":
			header.maxval, ok = strconv.parse_int(value)
			if !ok do return header, .Invalid_Maxval

		case "TUPLTYPE":
			if len(value) == 0 {
				return header, .Invalid_Tupltype
			}

			if len(tupltype.buf) == 0 {
				fmt.sbprint(&tupltype, value)
			} else {
				fmt.sbprint(&tupltype, "", value)
			}
		}
	}

	// extra info
	header.depth = 2 if header.maxval > int(max(u8)) else 1

	// limit checking
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
		return header, .Invalid_Channels_PAM_Depth
	}

	header.tupltype = strings.clone(strings.to_string(tupltype))

	return header, Error.None
}

@(private)
_parse_header_pfm :: proc(data: []byte) -> (header: Header, err: Error) {
	// we can just cycle through tokens for PFM
	field_iterator := string(data)

	field, ok := strings.fields_iterator(&field_iterator)

	switch field {
	case "Pf":
		header.format = .Pf
		header.channels = 1
	case "PF":
		header.format = .PF
		header.channels = 3
	case:
		return header, .Invalid_Signature
	}

	// floating point
	header.depth = 4

	// width
	field, ok = strings.fields_iterator(&field_iterator)
	if !ok do return header, .Invalid_Width
	header.width, ok = strconv.parse_int(field)
	if !ok do return header, .Invalid_Width

	// height
	field, ok = strings.fields_iterator(&field_iterator)
	if !ok do return header, .Invalid_Height
	header.height, ok = strconv.parse_int(field)
	if !ok do return header, .Invalid_Height

	// scale (sign is endianness)
	field, ok = strings.fields_iterator(&field_iterator)
	if !ok do return header, .Invalid_Scale
	header.scale, ok = strconv.parse_f32(field)
	if !ok do return header, .Invalid_Scale

	if header.scale < 0.0 {
		header.endianness = .Little
		header.scale = -header.scale
	}

	// pointer math to get header size
	header.total_bytes = int((uintptr(raw_data(field_iterator)) + 1) - uintptr(raw_data(data)))

	// limit checking
	if header.width < 1 {
		return header, .Invalid_Width
	}
	if header.height < 1 {
		return header, .Invalid_Height
	}
	if header.scale == 0.0 {
		return header, .Invalid_Scale
	}

	return header, Error.None
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
		//! PFM rows are bottom to top, is that important for us or just the caller
		mem.copy(raw_data(img.pixels.buf), raw_data(data), buffer_size)

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
			//? maybe endian conversion is not necessary
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
