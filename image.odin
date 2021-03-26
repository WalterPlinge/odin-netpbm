package odin_image

/* @TODO: ONLY SUPPORTS PPM P6 255 RIGHT NOW
	- Full PPM P6
		- Options struct
	- PPM P3
	- PPM P1,2,4,5
	- BMP
	...
	- JPG
	- PNG
*/

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:os"
import "core:unicode"

Pixel :: distinct [3]f64;

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




load_from_file :: proc(file: string) -> Image {
	// @TODO: error handling
	data, _ := os.read_entire_file(file);
	defer delete(data);
	return load_from_memory(data);
}

save_to_file :: proc(image: ^Image, file: string) {
	os.write_entire_file(file, save_to_memory(image));
}

load_from_memory :: proc(data: []byte) -> Image {
	ppm := _extract_ppm_header(data);

	image := create(ppm.width, ppm.height);

	for i in 0 ..< ppm.width * ppm.height {
		pixel_data := data[ppm.pixel_index:];
		// @TODO: handle 2 bytes per pixel value
		stride :: 3;
		index := i * stride;
		// @TODO: better way to convert to pixel?
		image.pixels[i] = Pixel {
			f64(pixel_data[index + 0]) * f64(ppm.depth),
			f64(pixel_data[index + 1]) * f64(ppm.depth),
			f64(pixel_data[index + 2]) * f64(ppm.depth),
		};
	}

	return image;
}

save_to_memory :: proc(using image: ^Image) -> []byte {
	// @TODO: Pass in option struct for depth and eventual format
	PPM_DEPTH :: 65535;
	CHANNELS  :: len(Pixel);

	header := fmt.tprintf("P6 %v %v %v\n", width, height, PPM_DEPTH);

	pixel_capacity := width * height * CHANNELS;
	if PPM_DEPTH > int(max(byte)) {
		pixel_capacity *= 2;
	}

	capacity := len(header) + pixel_capacity;

	sb := strings.make_builder(0, capacity);
	strings.write_string(&sb, header);

	if PPM_DEPTH <= int(max(byte)) {
		for p in &pixels {
			for c in p {
				strings.write_byte(&sb, byte(c * PPM_DEPTH));
			}
		}
	} else {
		// @TODO: irfanview expects big-endian, is this always the case?
		pixel_data := make([]u16be, width * height * CHANNELS);
		for p in &pixels {
			for c in p {
				v := u16be(u16(c * PPM_DEPTH));
				strings.write_bytes(&sb, mem.ptr_to_bytes(&v));
			}
		}
	}

	return transmute([]byte)strings.to_string(sb);
}

// @TODO: better way to hold header information?
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
	using header;

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
			// @TODO: error handling
			#partial switch Header_Fields(index) {
				case .Type:
					value, _ := strconv.parse_int(field[1:]);
					type = u8(value);
				case .Width:
					value, _ := strconv.parse_int(field);
					width = value;
				case .Height:
					value, _ := strconv.parse_int(field);
					height = value;
				case .Depth:
					value, _ := strconv.parse_int(field);
					depth = u16(value);
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
			pixel_index = u8(i + 1);
			break;
		}
	}

	return header;
}
