package odin_image



Float :: f32;

Pixel :: distinct [3]Float; // RGB

Image :: struct {
	width: int,
	height: int,
	pixels: [dynamic]Pixel,
}

create :: proc(width: int, height: int, allocator := context.allocator) -> Image {
	image := Image{ width, height, nil };
	init(&image, allocator);
	return image;
}

init :: proc(image: ^Image, allocator := context.allocator) {
	using image;
	pixels = make([dynamic]Pixel, width * height, allocator);
}

resize :: proc(image: ^Image, width, height: int) {
	image.width = width;
	image.height = height;
	resize_dynamic_array(&image.pixels, width * height);
}

delete_image :: proc(image: ^Image) {
	delete(image.pixels);
}

pixel_index :: proc(image: ^Image, x, y: int) -> int {
	return y * image.width + x;
}

pixel_at :: proc(image: ^Image, x, y: int) -> ^Pixel {
	using image;
	return &pixels[pixel_index(image, x, y)];
}
