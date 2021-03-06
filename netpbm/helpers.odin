package netpbm

import "core:bytes"
import "core:image"

destroy :: proc(img: ^image.Image) -> bool {
	if img == nil do return false

	//! TEMP CAST
	info, ok := img.metadata.(^image.PNG_Info)
	if !ok do return false

	bytes.buffer_destroy(&img.pixels)
	header_destroy(&((^Info)(info)).header)
	free(info)
	img.metadata = nil

	return true
}

header_destroy :: proc(using header: ^Header) {
	if format == .P7 && tupltype != "" {
		delete(tupltype)
		tupltype = ""
	}
}
