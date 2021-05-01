package odin_image

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:unicode"



// error types
PPM_Error :: enum {
	NONE,
	INVALID_HEADER_ID,
	INVALID_HEADER_TOKEN,
	BAD_READ,
}

// @XXX: PPM is either binary or ascii, store type value or just plain bool?
PPM_Options :: struct {
	ascii: bool,
	maxval: u16,
}

check_format_ppm :: proc(data: []byte) -> bool {
	magic := string(data[0:2]);
	return magic == "P3" || magic == "{6";
}



// FILE IO
save_to_file_ppm :: proc(
	image: ^Image,
	file: string,
	options := PPM_Options{ ascii = false, maxval = 255 },
	allocator := context.allocator,
) -> bool {
	data := save_to_memory_ppm(image, options, allocator);
	defer delete(data);
	return os.write_entire_file(file, data);
}

load_from_file_ppm :: proc(
	file: string,
	allocator := context.allocator,
) -> (
	image: Image,
	options: PPM_Options,
	error: PPM_Error,
) {
	data, ok := os.read_entire_file(file, allocator);
	if !ok {
		error = .BAD_READ;
		return;
	}
	defer delete(data);
	return load_from_memory_ppm(data, allocator);
}

// MEMORY IO
save_to_memory_ppm :: proc(
	image: ^Image,
	options: PPM_Options,
	allocator := context.allocator,
) -> []byte {
	// @XXX: can this function be optimised?

	// @HACK: only supports binary
	if options.ascii {
		return nil;
	}

	// format header string
	id := "P6";
	if options.ascii {
		id = "P3";
	}
	header := fmt.tprintf("%s %v %v %v\n", id, image.width, image.height, options.maxval);

	// Calculate capacity
	two_bytes_per_channel := u16(max(byte)) < options.maxval;
	pixel_capacity := image.width * image.height * _PPM_CHANNELS;
	if two_bytes_per_channel {
		pixel_capacity *= 2;
	}
	capacity := len(header) + pixel_capacity;

	// @HACK: handle failed allocation?
	// create byte buffer and copy header
	data := make([]byte, capacity, allocator);
	copy(data[:], header);

	// encode pixels to byte buffer, convenient slice for pixel data in buffer
	pixel_data := data[len(header):];
	if !two_bytes_per_channel {
		// for each pixel, start at its offset in the data
		for pixel, pixel_index in &image.pixels {
			pixel_offset := pixel_index * _PPM_CHANNELS;
			// for each channel, start at its offset in the data
			for ch, ch_index in pixel {
				ch_offset := pixel_offset + ch_index;
				value := math.saturate(ch) * Float(options.maxval);
				pixel_data[ch_offset] = byte(value);
			}
		}
	} else {
		STRIDE :: size_of(_PPM_Wide_Type);

		for pixel, pixel_index in &image.pixels {
			pixel_offset := pixel_index * _PPM_CHANNELS * STRIDE;
			for ch, ch_index in &pixel {
				ch_offset := pixel_offset + ch_index * STRIDE;
				value := _PPM_Wide_Type(math.saturate(ch) * Float(options.maxval));
				bytes := mem.ptr_to_bytes(&value);
				pixel_data[ch_offset + 0] = bytes[0];
				pixel_data[ch_offset + 1] = bytes[1];
			}
		}
	}

	return data;
}

load_from_memory_ppm :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (
	image: Image,
	options: PPM_Options,
	error: PPM_Error,
) {
	header, err := _read_header_ppm(data);
	if err != .NONE {
		error = err;
		return;
	}

	// @HACK: only supports P6
	if header.ascii {
		return image, options, .INVALID_HEADER_ID;
	}

	options = PPM_Options{ ascii = header.ascii, maxval = header.maxval };
	image = create(header.width, header.height, allocator);

	two_bytes_per_channel := u16(max(byte)) < header.maxval;
	if !two_bytes_per_channel {
		pixel_data := data[header.buffer_offset:];
		for i in 0 ..< image.width * image.height {
			offset := i * _PPM_CHANNELS;
			image.pixels[i] = Pixel {
				Float(pixel_data[offset + 0]) / Float(header.maxval),
				Float(pixel_data[offset + 1]) / Float(header.maxval),
				Float(pixel_data[offset + 2]) / Float(header.maxval),
			};
		}
	} else {
		pixel_data := mem.slice_data_cast([]_PPM_Wide_Type, data[header.buffer_offset:]);
		for i in 0 ..< image.width * image.height {
			offset := i * _PPM_CHANNELS;
			image.pixels[i] = Pixel {
				Float(pixel_data[offset + 0]) / Float(header.maxval),
				Float(pixel_data[offset + 1]) / Float(header.maxval),
				Float(pixel_data[offset + 2]) / Float(header.maxval),
			};
		}
	}

	return;
}



// 2 byte values are stored big-endian
@(private)
_PPM_Wide_Type :: u16be;

// RGB
@(private)
_PPM_CHANNELS :: 3;

@(private)
_PPM_Header :: struct {
	ascii: bool,
	width: int,
	height: int,
	maxval: u16,
	buffer_offset: int,
}

@(private)
_read_header_ppm :: proc(
	data: []byte,
) -> (
	header: _PPM_Header,
	error: PPM_Error,
) {
	// make sure magic number is valid
	id := string(data[0:2]);
	switch id {
		case "P3":
			header.ascii = true;
		case "P6":
			header.ascii = false;
		case:
			return header, .INVALID_HEADER_ID;
	}

	// fields
	width, height, maxval: int;
	header_fields := []^int{ &width, &height, &maxval };

	// states
	in_comment := false;
	already_in_space := true;
	current_field := 0;
	current_value := header_fields[0];

	loop:
	for d, i in data[len(id):] {
		// handle comments
		if in_comment {
			switch d {
				// comments only go up to next carriage return or line feed
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
			if current_field >= len(header_fields) {
				header.buffer_offset = i + len(id) + 1;
				break loop;
			}
			current_value = header_fields[current_field];
		} else {
			already_in_space = false;

			if !unicode.is_digit(rune(d)) {
				return header, .INVALID_HEADER_TOKEN;
			}

			val, _ := strconv.parse_int(string([]byte{ d }));
			current_value^ *= 10;
			current_value^ += val;
		}
	}

	header.width = width;
	header.height = height;
	header.maxval = u16(maxval);

	return;
}
