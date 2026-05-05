@use "github.com/jkroso/MiniFB.jl"... int
@use Skia
@use "./Geometric"...
@use "./Specific"...
@use "./draw" draw

"Render a draw function to a PNG file. `f(canvas, size, args...)` is called to draw.

`MiniFB.skia.sk_color` packs colors as 0xAABBGGRR but `sk_paint_set_color` reads them as 0xAARRGGBB,
so every R/B channel ends up swapped at the surface. The live window happens to swap them back
through a UInt32→ARGB32 reinterpret on little-endian. We compensate here by reading pixels back
in BGRA order (which un-swaps R/B at the byte level) and encoding those bytes as RGBA."
function save_png(f::Function, path::AbstractString, size, args...; scale=(2.0, 2.0))
  (scalex, scaley) = scale
  x, y = int.(size)
  scaledx = round(Int, x*scalex)
  scaledy = round(Int, y*scaley)
  rowbytes = Csize_t(scaledx * 4)
  surface_info = Ref(Skia.sk_image_info_t(C_NULL, Skia.sk_color_type_t(4), Skia.sk_alpha_type_t(1), scaledx, scaledy))
  bgra_dst   = Ref(Skia.sk_image_info_t(C_NULL, Skia.sk_color_type_t(6), Skia.sk_alpha_type_t(1), scaledx, scaledy))
  rgba_label = Ref(Skia.sk_image_info_t(C_NULL, Skia.sk_color_type_t(4), Skia.sk_alpha_type_t(1), scaledx, scaledy))
  pixels = Vector{UInt8}(undef, rowbytes * scaledy)
  GC.@preserve surface_info bgra_dst rgba_label pixels begin
    surface = Skia.sk_surface_make_raster_n32_premul(pointer_from_objref(surface_info), C_NULL)
    surface == C_NULL && error("Failed to create Skia surface ($(scaledx)x$(scaledy))")
    canvas = Skia.sk_surface_get_canvas(surface)
    Skia.sk_canvas_scale(canvas, Float32(scalex), Float32(scaley))
    invokelatest(f, canvas, size, args...)
    image = Skia.sk_surface_make_image_snapshot(surface)
    Skia.sk_image_read_pixels(image, pointer_from_objref(bgra_dst), pointer(pixels),
                              rowbytes, Int32(0), Int32(0), Skia.sk_image_caching_hint_t(0))
    skdata = Skia.sk_data_new_with_copy(pointer(pixels), Csize_t(length(pixels)))
    rgba_image = Skia.sk_image_new_raster_data(pointer_from_objref(rgba_label), skdata, rowbytes)
    encoded = Skia.sk_encode_png(C_NULL, rgba_image, Int32(6))
    n = Skia.sk_data_get_size(encoded)
    ptr = Skia.sk_data_get_data(encoded)
    write(path, unsafe_wrap(Array, Ptr{UInt8}(ptr), n))
    Skia.sk_data_unref(encoded)
    Skia.sk_image_unref(rgba_image)
    Skia.sk_data_unref(skdata)
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
