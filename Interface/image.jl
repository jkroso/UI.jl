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
the process, so layout and drawing can ask for it every frame. Images added with
`register_image` are found by their key.
"""
image_source(path::AbstractString) = get(_images, path) do
  get!(_images, abspath(path)) do
    isfile(path) || error("Image not found: $path")
    decode_image(read(path), path)
  end
end

decode_image(bytes::Vector{UInt8}, name) = begin
  data = Skia.sk_data_new_with_copy(pointer(bytes), UInt64(length(bytes)))
  image = Skia.sk_image_new_from_encoded(data)
  Skia.sk_data_unref(data)
  image == C_NULL && error("Skia could not decode $name")
  ImageSource(image, Skia.sk_image_get_width(image), Skia.sk_image_get_height(image))
end

"""
Make encoded image `bytes` (PNG, JPEG…) drawable as `Image(key)`. Use it for
images that don't live in a file, like icons fetched from the operating system.
"""
register_image(key::AbstractString, bytes::Vector{UInt8}) = (_images[String(key)] = decode_image(bytes, key); key)

"True when `key` was added with `register_image`, or its file was already decoded"
has_image(key::AbstractString) = haskey(_images, key)

"Width ÷ height of the image at `path`"
image_aspect(path::AbstractString) = begin
  src = image_source(path)
  src.width / src.height
end

export image_source, image_aspect, ImageSource, register_image, has_image
