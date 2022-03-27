package test

import "core:bytes"
import "core:fmt"
import "core:image"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

import "../netpbm"

FILE_NAME :: "p6.ppm"

main :: proc() {
	start := time.now(); defer fmt.eprintln("Time:", time.diff(start, time.now()))

	stdout: strings.Builder
	for t in ([]int{0, 3}) {
		imgs, err := netpbm.read_from_buffer(transmute([]byte) tests[t])
		fmt.sbprintln(&stdout, err)
		for y in 0 ..< imgs[0].height {
			for x in 0 ..< imgs[0].width {
				if imgs[0].pixels.buf[y * imgs[0].width + x] == 0 {
					fmt.sbprint(&stdout, ".")
				} else {
					fmt.sbprint(&stdout, "X")
				}
			}
			fmt.sbprintln(&stdout, "")
		}
	}
	fmt.println(strings.to_string(stdout))
	// fmt.println(imgs)
	// fmt.println((transmute(^netpbm.Header) imgs[0].metadata.(^image.PNG_Info))^)

	// for t in tests {
	// 	header, err := netpbm.parse_header(transmute([]byte) t)
	// 	fmt.println(err, "\n", header, "\n")
	// }

	// img := generate()
	// defer bytes.buffer_destroy(&img.pixels)
	// err := ppm.write(FILE_NAME, img)
	// if err != .None do fmt.println(err)

	// if len(os.args) == 2 && os.args[1] == "gen" {
	// 	img1, img2 := generate(), generate()
	// 	edit_image(&img2)
	// 	defer {
	// 		bytes.buffer_destroy(&img1.pixels)
	// 		bytes.buffer_destroy(&img2.pixels)
	// 	}
	// 	err := ppm.write_multiple_to_file(FILE_NAME, []ppm.Image{ img1, img2 })
	// 	if err != .None {
	// 		fmt.println(err)
	// 	}
	// 	return
	// }

	// for _ in 0 ..< 1 {
	// 	imgs, err := ppm.read_from_file(FILE_NAME)
	// 	defer ppm.destroy(imgs)
	// 	if err != .None {
	// 		fmt.println(err)
	// 		return
	// 	}

	// 	fmt.println("edit image")

	// 	//edit_image(&imgs[0])
	// 	imgs[0], imgs[1] = imgs[1], imgs[0]

	// 	fmt.println("save image")

	// 	err = ppm.write_multiple_to_file(FILE_NAME, imgs[:])

	// 	fmt.println("end")
	// }

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
	WIDTH  :: 200
	HEIGHT :: 100
	DEPTH  :: size_of(TYPE)

	img := image.Image{
		width = WIDTH,
		height = HEIGHT,
		channels = 3,
		depth = DEPTH * 8,
	}

	resize(&img.pixels.buf, img.width * img.height * img.channels * (DEPTH))

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

tests := []string{
	`P1
# feep.pbm
24 7
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 1 1 1 1 0 0 1 1 1 1 0 0 1 1 1 1 0 0 1 1 1 1 0
0 1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 1 0
0 1 1 1 0 0 0 1 1 1 0 0 0 1 1 1 0 0 0 1 1 1 1 0
0 1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 0 0 0 1 0 0 0 0
0 1 0 0 0 0 0 1 1 1 1 0 0 1 1 1 1 0 0 1 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
`,

	`P2
# feep.pgm
24 7
15
0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0
0  3  3  3  3  0  0  7  7  7  7  0  0 11 11 11 11  0  0 15 15 15 15  0
0  3  0  0  0  0  0  7  0  0  0  0  0 11  0  0  0  0  0 15  0  0 15  0
0  3  3  3  0  0  0  7  7  7  0  0  0 11 11 11  0  0  0 15 15 15 15  0
0  3  0  0  0  0  0  7  0  0  0  0  0 11  0  0  0  0  0 15  0  0  0  0
0  3  0  0  0  0  0  7  7  7  7  0  0 11 11 11 11  0  0 15  0  0  0  0
0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0
`,

	`P3
# feep.ppm
4 4
15
 0  0  0    0  0  0    0  0  0   15  0 15
 0  0  0    0 15  7    0  0  0    0  0  0
 0  0  0    0  0  0    0 15  7    0  0  0
15  0 15    0  0  0    0  0  0    0  0  0
`,

	"P4\n23 5\n\x79\xe7\x9e\x41\x04\x12\x71\xc7\x1e\x41\x04\x10\x41\xe7\x90",

	`P5
# feep.pgm
24 7
15
`,

	`P6
# feep.ppm
4 4
15
`,

	`P7
WIDTH 227
HEIGHT 149
DEPTH 3
MAXVAL 255
TUPLTYPE RGB
ENDHDR
`,

	`Pf
24 7
1.23
`,

	`PF
24 7
-2.34
`,
}

/*
Timer:
	start := time.now(); defer fmt.eprintln("Time:", time.diff(start, time.now()))
*/
