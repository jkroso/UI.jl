@use Skia

"A decoded raster image, cached by file path"
struct ImageSource
  raw::Ptr{Skia.sk_image_t}
  width::Int
  height::Int
end

const _images = Dict{String,ImageSource}()

"""
Decode the image at `path` with Skia. The decoded image is cached for the life of
the process, so layout and drawing can ask for it every frame.
"""
image_source(path::AbstractString) = get!(_images, abspath(path)) do
  isfile(path) || error("Image not found: $path")
  bytes = read(path)
  data = Skia.sk_data_new_with_copy(pointer(bytes), UInt64(length(bytes)))
  image = Skia.sk_image_new_from_encoded(data)
  Skia.sk_data_unref(data)
  image == C_NULL && error("Skia could not decode $path")
  ImageSource(image, Skia.sk_image_get_width(image), Skia.sk_image_get_height(image))
end

"Width ÷ height of the image at `path`"
image_aspect(path::AbstractString) = begin
  src = image_source(path)
  src.width / src.height
end

export image_source, image_aspect, ImageSource
