package odin_image

import "core:fmt"
import "core:mem"
import "core:strings"

Pixel :: distinct [ 3 ] u8;

Image :: struct {
	width: int,
	height: int,
	pixels: []Pixel,
}

new_image :: proc(width, height: int) -> Image {
	return Image{ width, height, make([]Pixel, width * height) };
}

delete_image :: proc(using image: ^Image) {
	delete(pixels);
}

pixel_index :: proc(w, x, y: int) -> int {
	return y * w + x;
}

pixel_at :: proc(using image: ^Image, x, y: int) -> ^Pixel {
	return &pixels[pixel_index(width, x, y)];
}



PPM_Type :: enum { P3, P6 }

image_to_ppm_string :: proc(using image: ^Image, type: PPM_Type) -> string {
	sb := strings.make_builder();

	// TODO: PPMs can have different colour depth
	PPM_DEPTH :: 255;

	switch type {
	case .P3:
		fmt.sbprintf(&sb, "P3 %d %d %d\n", width, height, PPM_DEPTH);
		for p in &pixels {
			fmt.sbprintf(&sb, "%d %d %d\n", p.r, p.g, p.b);
		}
	case .P6:
		fmt.sbprintf(&sb, "P6 %d %d %d\n%s", width, height, PPM_DEPTH, mem.slice_to_bytes(pixels));
	}

	return strings.to_string(sb);
}
