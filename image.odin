package odin_image

/*
	[x] saving
	[x] loading
	[x] 1 & 2 byte values
	[x] comments
	@TODO [ ] allocators
	@TODO [ ] errors
	@TODO [ ] P3
	@TODO [ ] P5 / P2 / P4 / P1
	@TODO [ ] Streams (memory / file / stream)
	@TODO [ ] P7 (PAM)
	@TODO [ ] PF / Pf (PFM)
	@XXX [ ] Other formats (BMP / JPG / PNG)
	@XXX: Gamma correction, is it necessary?
*/

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:os"
import "core:path"
import "core:unicode"



Float :: f32;
Pixel :: distinct [3]Float; // RGB
Image :: struct {
	width: int,
	height: int,
	pixels: [dynamic]Pixel,
}
create :: proc(width, height: int) -> Image {
	image := Image{ width, height, nil };
	init(&image);
	return image;
}
init :: proc(using image: ^Image) {
	pixels = make([dynamic]Pixel, width * height);
}
resize :: proc(image: ^Image, width, height: int) {
	image.width = width;
	image.height = height;
	resize_dynamic_array(&image.pixels, width * height);
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
load_from_file :: proc(file: string) -> (image: Image, options: Options) {
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
load_from_memory :: proc(data: []byte, image_format: Image_Format) -> (image: Image, options: Options) {
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
	type: u8,
	maxval: u16,
}
save_to_memory_ppm :: proc(image: ^Image, options: PPM_Options) -> []byte {
	// @XXX: can this function be optimised?

	// @XXX: only supports P6
	if options.type != 6 {
		return nil;
	}

	header := fmt.tprintf("P%v %v %v %v\n", options.type, image.width, image.height, options.maxval);

	// Calculate capacity
	pixel_capacity := image.width * image.height * _PPM_CHANNELS;
	if options.maxval > u16(max(byte)) {
		pixel_capacity *= 2;
	}
	capacity := len(header) + pixel_capacity;

	// @HACK: handle failed allocation?
	// Create byte buffer
	data := make([]byte, capacity);
	for i in 0 ..< len(header) {
		data[i] = header[i];
	}

	if options.maxval <= u16(max(byte)) {
		for px, px_idx in &image.pixels {
			px_in_data := len(header) + px_idx * _PPM_CHANNELS;
			for ch, ch_idx in px {
				ch_in_data := px_in_data + ch_idx;
				value := math.saturate(ch) * Float(options.maxval);
				data[ch_in_data] = byte(value);
			}
		}
	} else {
		STRIDE :: size_of(_PPM_Wide_Type);

		for px, px_idx in &image.pixels {
			px_in_data := len(header) + px_idx * _PPM_CHANNELS * STRIDE;
			for ch, ch_idx in px {
				ch_in_data := px_in_data + ch_idx * STRIDE;
				value := _PPM_Wide_Type(math.saturate(ch) * Float(options.maxval));
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
load_from_memory_ppm :: proc(data: []byte) -> (image: Image, options: PPM_Options) {
	header := _extract_ppm_header(data);

	// @XXX: only supports P6
	if header.type != 6 {
		return;
	}

	options = PPM_Options{ header.type, header.maxval };
	image = create(header.width, header.height);

	if header.maxval <= u16(max(byte)) {
		pixel_data := data[header.pixel_index:];
		for i in 0 ..< image.width * image.height {
			n := i * _PPM_CHANNELS;
			p := Pixel {
				Float(pixel_data[n + 0]) / Float(header.maxval),
				Float(pixel_data[n + 1]) / Float(header.maxval),
				Float(pixel_data[n + 2]) / Float(header.maxval),
			};
			image.pixels[i] = p;
		}
	} else {
		pixel_data := mem.slice_data_cast([]_PPM_Wide_Type, data[header.pixel_index:]);
		for i in 0 ..< image.width * image.height {
			n := i * _PPM_CHANNELS;
			p := Pixel {
				Float(pixel_data[n + 0]) / Float(header.maxval),
				Float(pixel_data[n + 1]) / Float(header.maxval),
				Float(pixel_data[n + 2]) / Float(header.maxval),
			};
			image.pixels[i] = p;
		}
	}

	return image, PPM_Options{ header.type, header.maxval };
}
@private
_extract_ppm_header :: proc(data: []byte) -> (header: _PPM_Header) {
	// @HACK: Add error support instead of asserting
	assert(data[0] == 'P', "Invalid PPM header (not a 'P' number)");
	assert(unicode.is_digit(rune(data[1])), "Invalid PPM header (bad number)");
	magic_num, _ := strconv.parse_int(string([]byte{data[1]}));
	assert(magic_num >= 1 && magic_num <= 6, "Invalid PPM header (invalid number)");

	header.type = u8(magic_num);

	// start pixel_index on 2 so we can skip magic number
	header.pixel_index = 2;

	// fields
	Fields :: enum {
		Type,
		Width,
		Height,
		Maxval,
		Count,
	};
	width, height, maxval := 0, 0, 0;

	in_comment := false;
	already_in_space := true;
	current_field := int(Fields.Width);
	current_value := &width;

	loop:
	for d, i in data[2:] {
		// current value being parsed

		// handle comments
		if in_comment {
			switch d {
				case '\r', '\n':
					in_comment = false;
			}
			continue;
		} else if d == '#' {
			in_comment = true;
			continue;
		}

		// handle whitespace
		in_space := unicode.is_white_space(rune(d));
		if in_space {
			// still in space
			if already_in_space {
				continue;
			}
			already_in_space = true;

			// switch to next value
			current_field += 1;
			switch Fields(current_field) {
				case .Height:
					current_value = &height;
				case .Maxval:
					current_value = &maxval;
				case .Type, .Width, .Count:
					// payload starts on next byte (already has 2 for magic number)
					header.pixel_index += i + 1;
					break loop;
			}
		} else {
			already_in_space = false;

			assert(unicode.is_digit(rune(d)), "Invalid PPM header (malformed token)");
			str := []byte{ d };
			val, _ := strconv.parse_int(string(str));
			current_value^ *= 10;
			current_value^ += val;
		}
	}

	header.width = width;
	header.height = height;
	header.maxval = u16(maxval);

	return;
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
	maxval: u16,
	pixel_index: int,
}
