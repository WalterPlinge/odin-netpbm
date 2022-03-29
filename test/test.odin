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
	colours := []rune{'.', '-', '=', '@', '#'}

	for t in ([]int{0, 3, 1, 4, 2, 5}) {
		img, err := netpbm.read_from_buffer(transmute([]byte) tests[t]); defer netpbm.destroy_image(&img)
		fmt.sbprintln(&stdout, err)

		header := (transmute(^netpbm.Header) img.metadata.(^image.PNG_Info))^
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
