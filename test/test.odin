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

	write_tests()
	if true do return

	stdout: strings.Builder
	colours := []rune{'.', '-', '=', '@', '#'}

	for t in ([]int{0, 3, 1, 4, 2, 5}) {
		img, err := netpbm.read_from_buffer(transmute([]byte) tests[t]); defer netpbm.destroy(&img)
		fmt.sbprintln(&stdout, err)

		header := (cast(^netpbm.Info) img.metadata.(^image.PNG_Info)).header
		fmt.sbprintln(&stdout, header.format)

		if header.format in netpbm.PPM {
			pixels := mem.slice_data_cast([][3]u8, img.pixels.buf[:])
			for y in 0 ..< img.height {
				for x in 0 ..< img.width {
					pix := pixels[y * img.width + x]
					for p in pix {
						v := p
						if v == 1 && header.maxval == 1 {
							v = 4
						}
						fmt.sbprint(&stdout, colours[v])
					}
					fmt.sbprint(&stdout, " ")
				}
				fmt.sbprintln(&stdout, "")
			}
			continue
		}

		for y in 0 ..< img.height {
			for x in 0 ..< img.width {
				v := img.pixels.buf[y * img.width + x]
				if v == 1 && header.maxval == 1 {
					v = 4
				}
				fmt.sbprint(&stdout, colours[v])
			}
			fmt.sbprintln(&stdout, "")
		}
	}
	fmt.println(strings.to_string(stdout))

	return
}

write_tests :: proc() {
	{ // P1
		img: image.Image
		img.width = 2
		img.height = 2
		img.channels = 1
		img.depth = 1

		resize(&img.pixels.buf, img.width * img.height)
		img.pixels.buf[0] = 1
		img.pixels.buf[1] = 0
		img.pixels.buf[2] = 0
		img.pixels.buf[3] = 1

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P1

		err := netpbm.write("p1.pbm", img)
		fmt.println("P1", err)
	}

	{ // P2
		img: image.Image
		img.width = 20
		img.height = 20
		img.channels = 1
		img.depth = 1

		resize(&img.pixels.buf, img.width * img.height)
		for y in 0 ..< img.height {
			v := f32(y) / f32(img.height)
			for x in 0 ..< img.width {
				u := f32(x) / f32(img.width)
				i := y * img.width + x
				img.pixels.buf[i] = byte(127.0 * (u + v))
			}
		}

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P2
		info.header.maxval = 255

		err := netpbm.write("p2.pgm", img)
		fmt.println("P2", err)
	}

	{ // P3
		img: image.Image
		img.width = 20
		img.height = 20
		img.channels = 3
		img.depth = 1

		resize(&img.pixels.buf, img.width * img.height * img.channels)
		pixels := mem.slice_data_cast([][3]u8, img.pixels.buf[:])
		for y in 0 ..< img.height {
			v := f32(y) / f32(img.height)
			for x in 0 ..< img.width {
				u := f32(x) / f32(img.width)
				i := y * img.width + x
				p := &pixels[i]
				p.r = u8(255.0 * u)
				p.g = u8(255.0 * v)
			}
		}

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P3
		info.header.maxval = 255

		err := netpbm.write("p3.ppm", img)
		fmt.println("P3", err)
	}

	{ // P4
		img: image.Image
		img.width = 2
		img.height = 2
		img.channels = 1
		img.depth = 1

		resize(&img.pixels.buf, img.width * img.height)
		img.pixels.buf[0] = 1
		img.pixels.buf[1] = 0
		img.pixels.buf[2] = 0
		img.pixels.buf[3] = 1

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P4

		err := netpbm.write("p4.pbm", img)
		fmt.println("P4", err)
	}

	{ // P5
		img: image.Image
		img.width = 20
		img.height = 20
		img.channels = 1
		img.depth = 1

		resize(&img.pixels.buf, img.width * img.height)
		for y in 0 ..< img.height {
			v := f32(y) / f32(img.height)
			for x in 0 ..< img.width {
				u := f32(x) / f32(img.width)
				i := y * img.width + x
				img.pixels.buf[i] = byte(127.0 * (u + v))
			}
		}

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P5
		info.header.maxval = 255

		err := netpbm.write("p5.pgm", img)
		fmt.println("P5", err)
	}

	{ // P6
		img: image.Image
		img.width = 20
		img.height = 20
		img.channels = 3
		img.depth = 1

		resize(&img.pixels.buf, img.width * img.height * img.channels)
		pixels := mem.slice_data_cast([][3]u8, img.pixels.buf[:])
		for y in 0 ..< img.height {
			v := f32(y) / f32(img.height)
			for x in 0 ..< img.width {
				u := f32(x) / f32(img.width)
				i := y * img.width + x
				p := &pixels[i]
				p.r = u8(255.0 * u)
				p.g = u8(255.0 * v)
			}
		}

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P6
		info.header.maxval = 255

		err := netpbm.write("p6.ppm", img)
		fmt.println("P6", err)
	}

	{ // P7
		img: image.Image
		img.width = 20
		img.height = 20
		img.channels = 3
		img.depth = 1

		resize(&img.pixels.buf, img.width * img.height * img.channels)
		pixels := mem.slice_data_cast([][3]u8, img.pixels.buf[:])
		for y in 0 ..< img.height {
			v := f32(y) / f32(img.height)
			for x in 0 ..< img.width {
				u := f32(x) / f32(img.width)
				i := y * img.width + x
				p := &pixels[i]
				p.r = u8(255.0 * u)
				p.g = u8(255.0 * v)
			}
		}

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P7
		info.header.maxval = 255
		info.header.tupltype = "RGB"

		err := netpbm.write("p7.pam", img)
		fmt.println("P7", err)
	}

	{ // P7 to P6
		img, err := netpbm.read("p7.pam")
		fmt.println("P7 read", err)
		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .P6
		info.header.maxval = 255
		err = netpbm.write("p76.ppm", img)
		fmt.println("P76", err)
	}

	{ // Pf
		img: image.Image
		img.width = 20
		img.height = 20
		img.channels = 1
		img.depth = 4

		resize(&img.pixels.buf, img.width * img.height * img.channels * img.depth)
		pixels := mem.slice_data_cast([]f32, img.pixels.buf[:])
		for y in 0 ..< img.height {
			i := y
			v := f32(y) / f32(img.height)
			for x in 0 ..< img.width {
				i := i * img.width + x
				u := f32(x) / f32(img.width)
				p := &pixels[i]
				p^ = (u + v) / 2.0
			}
		}

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .Pf
		info.header.scale = 1.0
		info.header.endian = .Little

		err := netpbm.write("pf1.pfm", img)
		fmt.println("Pf", err)
	}

	{ // PF
		img: image.Image
		img.width = 20
		img.height = 20
		img.channels = 3
		img.depth = 4

		resize(&img.pixels.buf, img.width * img.height * img.channels * img.depth)
		pixels := mem.slice_data_cast([][3]f32, img.pixels.buf[:])
		for y in 0 ..< img.height {
			i := y
			v := f32(y) / f32(img.height)
			for x in 0 ..< img.width {
				i := i * img.width + x
				u := f32(x) / f32(img.width)
				p := &pixels[i]
				p.r = u
				p.g = v
			}
		}

		info: netpbm.Info
		img.metadata = cast(^image.PNG_Info) &info
		info.header.format = .PF
		info.header.scale = 1.0
		info.header.endian = .Big

		err := netpbm.write("pf3.pfm", img)
		fmt.println("PF", err)
	}
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
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 1 1 1 1 0 0 2 2 2 2 0 0 3 3 3 3 0 0 4 4 4 4 0
0 1 0 0 0 0 0 2 0 0 0 0 0 3 0 0 0 0 0 4 0 0 4 0
0 1 1 1 0 0 0 2 2 2 0 0 0 3 3 3 0 0 0 4 4 4 4 0
0 1 0 0 0 0 0 2 0 0 0 0 0 3 0 0 0 0 0 4 0 0 0 0
0 1 0 0 0 0 0 2 2 2 2 0 0 3 3 3 3 0 0 4 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
`,

`P3
# feep.ppm
4 4
2
0  0  0    0  0  0    0  0  0    2  0  2
0  0  0    0  2  1    0  0  0    0  0  0
0  0  0    0  0  0    0  2  1    0  0  0
2  0  2    0  0  0    0  0  0    0  0  0
`,

"P4\n23 5\n\x79\xe7\x9e\x41\x04\x12\x71\xc7\x1e\x41\x04\x10\x41\xe7\x90",

"P5\n22 5\n4\n\x01\x01\x01\x01\x00\x00\x02\x02\x02\x02\x00\x00\x03\x03\x03\x03\x00\x00\x04\x04\x04\x04\x01\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x03\x00\x00\x00\x00\x00\x04\x00\x00\x04\x01\x01\x01\x00\x00\x00\x02\x02\x02\x00\x00\x00\x03\x03\x03\x00\x00\x00\x04\x04\x04\x04\x01\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x03\x00\x00\x00\x00\x00\x04\x00\x00\x00\x01\x00\x00\x00\x00\x00\x02\x02\x02\x02\x00\x00\x03\x03\x03\x03\x00\x00\x04\x00\x00\x00",

"P6\n4 4\n15\n\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x02\x00\x00\x00\x00\x02\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x01\x00\x00\x00\x02\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00",

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
