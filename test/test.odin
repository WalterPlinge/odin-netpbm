package test

// import "core:fmt"
// import "core:time"

import img ".."

main :: proc() {
	if false {
		generate();
		return;
	}

	image, options, _ := img.load_from_file("P6.ppm", .PPM);
	defer img.delete_image(&image);

	edit_image(&image);

	img.save_to_file(&image, "P6.ppm", options);
}

edit_image :: proc (
	image : ^img.Image,
) {
	for p in &image.pixels {
		p.r, p.g, p.b = p.b, p.r, p.g;
	}
}

generate :: proc() {
	HEIGHT :: 5;
	WIDTH  :: HEIGHT * 2;
	DEPTH  :: 0xFF;//FF;
	image := img.create(WIDTH, HEIGHT);
	defer img.delete_image(&image);
	using image;

	for y in 0 ..< height {
		for x in 0 ..< width {
			p := img.pixel_at(&image, x, y);
			p.r = img.Float(x) / img.Float(width);
			p.g = img.Float(y) / img.Float(height);
		}
	}

	options := img.PPM_Options{
		ascii = false,
		maxval = DEPTH,
	};
	img.save_to_file(&image, "P6.ppm", options);
}

/*
Timer:
	start := time.now();
	defer fmt.eprintln("Time:", time.diff(start, time.now()));
*/
