package odin_image

/*
	- ! ONLY SUPPORTS PPM P6 RIGHT NOW
	@TODO: Load returns options to use for similar save
	@XXX: Gamma correction, is it necessary?
	- PPM P3
	- PPM P1,2,4,5
	- Buffered reading from file (big files)
	- BMP
	...
	- JPG
	- PNG
*/

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:os"
import "core:path"
import "core:unicode"



Float :: f64;
Pixel :: distinct [3]Float;
Image :: struct {
	width: int,
	height: int,
	pixels: []Pixel,
}
init :: proc(using image: ^Image) {
	pixels = make([]Pixel, width * height);
}
create :: proc(width, height: int) -> Image {
	image := Image{ width, height, nil };
	init(&image);
	return image;
}
delete_image :: proc(using image: ^Image) {
	delete(pixels);
}
pixel_index :: proc(using image: ^Image, x, y: int) -> int {
	return y * width + x;
}
pixel_at :: proc(using image: ^Image, x, y: int) -> ^Pixel {
	return &pixels[pixel_index(image, x, y)];
}



Image_Format :: enum {
	PPM,
}
Options :: union {
	PPM_Options,
}
load_from_file :: proc(file: string) -> (image: Image) {
	// @FIXME: error handling
	data, _ := os.read_entire_file(file);
	defer delete(data);

	file_formats := map[string]Image_Format{
		".PPM" = .PPM,
	};

	ext := strings.to_upper(path.ext(file));
	format, found := file_formats[ext];
	// @HACK: error handling
	if !found {
		return;
	}

	return load_from_memory(data, format);
}
save_to_file :: proc(image: ^Image, file: string, options: Options) {
	data := save_to_memory(image, options);
	// @HACK: error handling
	if data == nil {
		return;
	}
	defer delete(data);

	// @FIXME: error handling
	os.write_entire_file(file, data);
}
load_from_memory :: proc(data: []byte, image_format: Image_Format) -> (image: Image) {
	switch image_format {
		case .PPM:
			return load_from_memory_ppm(data);
	}
	return;
}
save_to_memory :: proc(image: ^Image, options: Options) -> []byte {
	switch o in options {
		case PPM_Options:
			return save_to_memory_ppm(image, o);
	}
	return nil;
}



PPM_Options :: struct {
	depth: u16,
}
save_to_memory_ppm :: proc(using image: ^Image, options: PPM_Options) -> []byte {
	// @XXX: can this function be optimised?

	header := fmt.tprintf("P6 %v %v %v\n", width, height, options.depth);

	// Calculate capacity
	pixel_capacity := width * height * _PPM_CHANNELS;
	if options.depth > u16(max(byte)) {
		pixel_capacity *= 2;
	}
	capacity := len(header) + pixel_capacity;

	// Create byte buffer
	data := make([]byte, capacity);
	for i in 0 ..< len(header) {
		data[i] = header[i];
	}

	if options.depth <= u16(max(byte)) {
		for px, px_idx in &pixels {
			px_in_data := len(header) + px_idx * _PPM_CHANNELS;
			for ch, ch_idx in px {
				ch_in_data := px_in_data + ch_idx;
				value := math.saturate(ch) * Float(options.depth);
				data[ch_in_data] = byte(value);
			}
		}
	} else {
		STRIDE :: size_of(_PPM_Wide_Type);

		for px, px_idx in &pixels {
			px_in_data := len(header) + px_idx * _PPM_CHANNELS * STRIDE;
			for ch, ch_idx in px {
				ch_in_data := px_in_data + ch_idx * STRIDE;
				value := _PPM_Wide_Type(math.saturate(ch) * Float(options.depth));
				bytes := mem.ptr_to_bytes(&value);
				for b, b_idx in bytes {
					b_in_data := ch_in_data + b_idx;
					data[b_in_data] = b;
				}
			}
		}
	}

	return data;
}
load_from_memory_ppm :: proc(data: []byte) -> Image {
	header := _extract_ppm_header(data);
	using header;

	image := create(width, height);

	if depth <= u16(max(byte)) {
		pixel_data := data[pixel_index:];
		for i in 0 ..< width * height {
			n := i * _PPM_CHANNELS;
			p := Pixel {
				Float(pixel_data[n + 0]) / Float(depth),
				Float(pixel_data[n + 1]) / Float(depth),
				Float(pixel_data[n + 2]) / Float(depth),
			};
			image.pixels[i] = p;
		}
	} else {
		pixel_data := mem.slice_data_cast([]_PPM_Wide_Type, data[pixel_index:]);
		for i in 0 ..< width * height {
			n := i * _PPM_CHANNELS;
			p := Pixel {
				Float(pixel_data[n + 0]) / Float(depth),
				Float(pixel_data[n + 1]) / Float(depth),
				Float(pixel_data[n + 2]) / Float(depth),
			};
			image.pixels[i] = p;
		}
	}

	return image;
}
@private
_PPM_Wide_Type :: u16be;
@private
_PPM_CHANNELS :: 3; // RGB
@private
_PPM_Header :: struct {
	type: u8,
	width: int,
	height: int,
	depth: u16,
	pixel_index: u8,
}
@private
_extract_ppm_header :: proc(data: []byte) -> (header: _PPM_Header) {
	Header_Fields :: enum int {
		Type,
		Width,
		Height,
		Depth,
		Count,
	};

	// current header field being scanned, and range of field text
	index := 0;
	start, end := 0, 0;
	already_in_space := true;

	for d, i in data {
		is_space := unicode.is_space(rune(d));

		// do nothing if we havn't changed from field to space or vice versa
		if is_space == already_in_space {
			continue;
		}

		// now in space, set header field to current range
		if is_space {
			end = i;

			field := string(data[start : end]);
			// @FIXME: error handling
			#partial switch Header_Fields(index) {
				case .Type:
					value, _ := strconv.parse_int(field[1:]);
					header.type = u8(value);
				case .Width:
					value, _ := strconv.parse_int(field);
					header.width = value;
				case .Height:
					value, _ := strconv.parse_int(field);
					header.height = value;
				case .Depth:
					value, _ := strconv.parse_int(field);
					header.depth = u16(value);
			}

			index += 1;
			already_in_space = true;
		}
		// no longer in space, reset start of range
		else {
			start = i;
			already_in_space = false;
		}

		// break when you reach the data, which follows after single whitespace
		if index >= int(Header_Fields.Count) {
			header.pixel_index = u8(i + 1);
			break;
		}
	}

	return header;
}
