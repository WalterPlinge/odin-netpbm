package odin_image

/* @TODO: ONLY SUPPORTS PPM P6 RIGHT NOW
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




load_from_file :: proc(file: string) -> Image {
	// @FIXME: error handling
	data, _ := os.read_entire_file(file);
	defer delete(data);
	return load_from_memory(data);
}

save_to_file :: proc(image: ^Image, file: string) {
	data := save_to_memory(image);
	defer delete(data);
	// @FIXME: error handling
	os.write_entire_file(file, data);
}

load_from_memory :: proc(data: []byte) -> Image {
	// @HACK: handle channels better plz
	CHANNELS :: len(Pixel);

	ppm := _extract_ppm_header(data);
	using ppm;

	image := create(width, height);

	if depth <= u16(max(byte)) {
		pixel_data := data[pixel_index:];
		for i in 0 ..< width * height {
			n := i * CHANNELS;
			image.pixels[i] = Pixel {
				Float(pixel_data[n + 0]) / Float(depth),
				Float(pixel_data[n + 1]) / Float(depth),
				Float(pixel_data[n + 2]) / Float(depth),
			};
		}
	} else {
		pixel_data := mem.slice_data_cast([]u16be, data[pixel_index:]);
		for i in 0 ..< width * height {
			n := i * CHANNELS;
			image.pixels[i] = Pixel {
				// @HACK: endian-ness is broken, cast to base type first
				Float(u16(pixel_data[n + 0])) / Float(depth),
				Float(u16(pixel_data[n + 1])) / Float(depth),
				Float(u16(pixel_data[n + 2])) / Float(depth),
			};
		}
	}

	return image;
}

save_to_memory :: proc(using image: ^Image) -> []byte {
	// @XXX: can this function be optimised?

	// @TODO: pass in option struct for depth and eventual format
	PPM_DEPTH :: 65535;
	// @HACK: handle channels better plz
	CHANNELS  :: len(Pixel);

	header := fmt.tprintf("P6 %v %v %v\n", width, height, PPM_DEPTH);

	pixel_capacity := width * height * CHANNELS;
	if PPM_DEPTH > int(max(byte)) {
		pixel_capacity *= 2;
	}

	capacity := len(header) + pixel_capacity;

	data := make([]byte, capacity);
	for i in 0 ..< len(header) {
		data[i] = header[i];
	}

	if PPM_DEPTH <= int(max(byte)) {
		for px, px_idx in &pixels {
			px_in_data := len(header) + px_idx * CHANNELS;
			for ch, ch_idx in px {
				ch_in_data := px_in_data + ch_idx;
				data[ch_in_data] = byte(ch * PPM_DEPTH);
			}
		}
	} else {
		// @XXX: irfanview expects big-endian, is this always the case?
		for px, px_idx in &pixels {
			px_in_data := len(header) + px_idx * CHANNELS * 2;
			for ch, ch_idx in px {
				ch_in_data := px_in_data + ch_idx * 2;
				// @HACK: endian-ness is broken, cast to base type first
				value := u16be(u16(ch * PPM_DEPTH));
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

// @XXX: better way to hold header information?
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
			// @FIXME: error handling
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
