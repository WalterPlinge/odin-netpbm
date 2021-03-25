package main

import img ".."

main :: proc() {
	if true {
		generate();
		return;
	}

	image := img.load_from_file("P6.ppm");
	defer img.delete_image(&image);

	for y in 0 ..< image.height {
		for x in 0 ..< image.width {
			p := img.pixel_at(&image, x, y);
			//p.b = (p.b + 128) % 255;
			p.r, p.g, p.b = p.b, p.r, p.g;
		}
	}

	img.save_to_file(&image, "P6.ppm");
}

generate :: proc() {
	image := img.create(200, 100);
	defer img.delete_image(&image);
	using image;

	for y in 0 ..< height {
		for x in 0 ..< width {
			p := img.pixel_at(&image, x, y);
			p.r = f64(x) / f64(width);
			p.g = f64(y) / f64(height);
		}
	}

	img.save_to_file(&image, "P6.ppm");
}
