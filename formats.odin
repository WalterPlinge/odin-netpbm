package odin_image

/*
	[x] saving
	[x] loading
	[x] 1 & 2 byte values
	[x] comments
	[x] allocators
	@TODO [-] errors
	@TODO [ ] P3
	@TODO [ ] P5 / P2 / P4 / P1
	@TODO [ ] Streams (memory / file / stream)
	@TODO [ ] P7 (PAM)
	@TODO [ ] PF / Pf (PFM)
	@XXX [ ] Other formats (BMP / JPG / PNG)
	@XXX: Gamma correction, is it necessary?
*/



Image_Format :: enum {
	UNKNOWN,
	USE_EXTENSION,
	PPM,
}

Options :: union {
	PPM_Options,
}

Error :: union {
	PPM_Error,
}



load_from_file :: proc(
	file: string,
	format := Image_Format.USE_EXTENSION,
	allocator := context.allocator,
) -> (
	image: Image,
	options: Options,
	error: Error,
) {
	switch format {
		case .PPM:
			return load_from_file_ppm(file, allocator);
		case .USE_EXTENSION:
			// @TODO: find format using known file extensions
			// @HACK: can recurse to make it simpler
		case .UNKNOWN:
			// @TODO: loop through "check_format" functions until one of them succeeds
			// @HACK
	}
	// @XXX: do I need an error here?
	return;
}

load_from_memory :: proc(
	data: []byte,
	format := Image_Format.UNKNOWN,
	allocator := context.allocator,
) -> (
	image: Image,
	options: Options,
	error: Error,
) {
	switch format {
		case .PPM:
			return load_from_memory_ppm(data, allocator);
		case .UNKNOWN, .USE_EXTENSION:
			// @TODO: check data format
			// @HACK: cannot use extensions on memory so treat it as unknown
	}
	// @XXX: do I need an error here?
	return;
}

save_to_file :: proc(
	image: ^Image,
	file: string,
	options: Options = PPM_Options{ ascii = false, maxval = 255 },
	allocator := context.allocator,
) -> bool {
	switch o in options {
		case PPM_Options:
			return save_to_file_ppm(image, file, o, allocator);
	}
	return false;
}

save_to_memory :: proc(
	image: ^Image,
	options: Options = PPM_Options{ ascii = false, maxval = 255 },
	allocator := context.allocator,
) -> []byte {
	switch o in options {
		case PPM_Options:
			return save_to_memory_ppm(image, o, allocator);
	}
	return nil;
}
