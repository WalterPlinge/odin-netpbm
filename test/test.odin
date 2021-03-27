package test

import "core:fmt"
import "core:time"

import img ".."

DEPTH :: 65535;

main :: proc() {
	if false {
		generate();
		return;
	}

	start : time.Time;
	start = time.now();
	image := img.load_from_file("P6.ppm");
	fmt.eprintln("Time (load):", time.diff(start, time.now()));
	defer img.delete_image(&image);

	for p in &image.pixels {
		p.r, p.g, p.b = p.b, p.r, p.g;
	}

	start = time.now();
	img.save_to_file(&image, "P6.ppm", img.PPM_Options{ depth = DEPTH });
	fmt.eprintln("Time (save):", time.diff(start, time.now()));
}

generate :: proc() {
	HEIGHT :: 8;
	image := img.create(HEIGHT << 1, HEIGHT);
	defer img.delete_image(&image);
	using image;

	for y in 0 ..< height {
		for x in 0 ..< width {
			p := img.pixel_at(&image, x, y);
			p.r = img.Float(x) / img.Float(width);
			p.g = img.Float(y) / img.Float(height);
		}
	}

	img.save_to_file(&image, "P6.ppm", img.PPM_Options{ depth = DEPTH });
}

/*
Timer:
	start := time.now();
	defer fmt.eprintln("Time:", time.diff(start, time.now()));
*/
