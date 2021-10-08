package test

import "core:bytes"
import "core:fmt"
import "core:image"
import "core:mem"
import "core:os"
// import "core:time"

import "../ppm"

FILE_NAME :: "p6.ppm"

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "gen" {
		img := generate()
		defer bytes.buffer_destroy(&img.pixels)
		data, err := ppm.save(&img)
		if err != .None {
			fmt.println(err)
			return
		}
		if !os.write_entire_file(FILE_NAME, data) {
			fmt.println("error writing entire file")
			return
		}
		return
	}

	fmt.println("read file")

	file, ok := os.read_entire_file(FILE_NAME)
	if !ok {
		fmt.println("error reading entire file")
		return
	}

	fmt.println("load file")

	img, err := ppm.load(file)
	defer free(img)
	defer bytes.buffer_destroy(&img.pixels)
	if err != .None {
		fmt.println(err)
		return
	}

	fmt.println("edit image")

	edit_image(img)

	fmt.println("save image")

	data: []byte
	data, err = ppm.save(img)
	if err != .None {
		fmt.println(err)
		return
	}

	fmt.println("write file")

	if !os.write_entire_file(FILE_NAME, data) {
		fmt.println("error writing entire file 2")
		return
	}

	fmt.println("end")

	return
}

TYPE   :: u16

edit_image :: proc (
	img: ^image.Image,
) {
	pixel_data := mem.slice_data_cast([][3]TYPE, img.pixels.buf[:])
	for p in &pixel_data {
		p.r, p.g, p.b = p.b, p.r, p.g;
	}
}

generate :: proc() -> image.Image {
	BITS_PER_BYTE :: 8
	HEIGHT :: 5
	WIDTH  :: HEIGHT * 2
	DEPTH  :: size_of(TYPE) * BITS_PER_BYTE

	img := image.Image{
		width = WIDTH,
		height = HEIGHT,
		channels = 3,
		depth = DEPTH,
	}

	resize(&img.pixels.buf, img.width * img.height * img.channels * (DEPTH / BITS_PER_BYTE))

	pixel_data := mem.slice_data_cast([][3]TYPE, img.pixels.buf[:])
	pixel_index :: proc(img: ^image.Image, x, y: int) -> int {
		return y * img.width + x
	}

	for y in 0 ..< img.height {
		for x in 0 ..< img.width {
			p := &pixel_data[pixel_index(&img, x, y)]
			p.r = TYPE(f32(max(TYPE)) * f32(x) / f32(img.width))
			p.g = TYPE(f32(max(TYPE)) * f32(y) / f32(img.height))
		}
	}

	return img
}

/*
Timer:
	start := time.now();
	defer fmt.eprintln("Time:", time.diff(start, time.now()));
*/
