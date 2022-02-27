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
		img1, img2 := generate(), generate()
		edit_image(&img2)
		defer {
			bytes.buffer_destroy(&img1.pixels)
			bytes.buffer_destroy(&img2.pixels)
		}
		err := ppm.write_multiple_to_file(FILE_NAME, []ppm.Image{ img1, img2 })
	} else {
		for _ in 0 ..< 1 {
			imgs, err := ppm.read_from_file(FILE_NAME)
			defer ppm.destroy(imgs)
			if err != .None {
				fmt.println(err)
				return
			}

			fmt.println("edit image")

			//edit_image(&imgs[0])
			imgs[0], imgs[1] = imgs[1], imgs[0]

			fmt.println("save image")

			err = ppm.write_multiple_to_file(FILE_NAME, imgs[:])

			fmt.println("end")
		}
	}

	return
}

TYPE :: u8

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
	WIDTH  :: 1920
	HEIGHT :: 1080
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
	start := time.now(); defer fmt.eprintln("Time:", time.diff(start, time.now()))
*/
