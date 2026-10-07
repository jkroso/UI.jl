@use "github.com/jkroso/MiniFB.jl"... int
@use Skia
@use "./Geometric"...
@use "./Specific"...
@use "./draw" draw

"""
Render a draw function to a PNG file. `f(canvas, size, args...)` is called to draw.
With `opaque=false` the image starts out transparent, so the parts `f` doesn't
draw on stay see-through, e.g. the corners of an app icon.
"""
function save_png(f::Function, path::AbstractString, size, args...; scale=(2.0, 2.0), opaque=true)
  (scalex, scaley) = scale
  x, y = int.(size)
  scaledx = round(Int, x*scalex)
  scaledy = round(Int, y*scaley)
  info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_RGBA_8888, opaque ? Skia.SK_ALPHA_TYPE_OPAQUE : Skia.SK_ALPHA_TYPE_PREMUL, scaledx, scaledy))
  GC.@preserve info begin
    surface = Skia.sk_surface_make_raster_n32_premul(pointer_from_objref(info), C_NULL)
    surface == C_NULL && error("Failed to create Skia surface ($(scaledx)x$(scaledy))")
    canvas = Skia.sk_surface_get_canvas(surface)
    opaque || Skia.sk_canvas_clear(canvas, 0x00000000)
    Skia.sk_canvas_scale(canvas, Float32(scalex), Float32(scaley))
    invokelatest(f, canvas, size, args...)
    image = Skia.sk_surface_make_image_snapshot(surface)
    encoded = Skia.sk_encode_png(C_NULL, image, Int32(6))
    n = Skia.sk_data_get_size(encoded)
    ptr = Skia.sk_data_get_data(encoded)
    write(path, unsafe_wrap(Array, Ptr{UInt8}(ptr), n))
    Skia.sk_data_unref(encoded)
    Skia.sk_image_unref(image)
    Skia.sk_surface_unref(surface)
  end
  path
end

"Resolve a GeometricUI scene at the given size and save it as a PNG.
Renders through the same `draw` pipeline used for live windows so output stays
in sync with on-screen rendering."
save_scene(path::AbstractString, scene::Container, size) =
  save_png(draw, path, size, describe(scene, size))

export save_png, save_scene
