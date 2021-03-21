package main

import "core:os"

import img ".."

main :: proc() {
	WIDTH  :: 200;
	HEIGHT :: 100;

	image := img.new_image(WIDTH, HEIGHT);
	defer img.delete_image(&image);

	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			p := img.pixel_at(&image, x, y);
			p.r = u8(255 * f64(x) / f64(WIDTH));
			p.g = u8(255 * f64(y) / f64(HEIGHT));
		}
	}

	os.write_entire_file("P3.ppm", transmute([]byte)img.image_to_ppm_string(&image, .P3));

	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			p := img.pixel_at(&image, x, y);
			p.g = u8(255 * f64(x) / f64(WIDTH));
			p.r = u8(255 * f64(y) / f64(HEIGHT));
		}
	}

	os.write_entire_file("P6.ppm", transmute([]byte)img.image_to_ppm_string(&image, .P6));
}
