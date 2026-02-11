@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont
@use "github.com/jkroso/MiniFB.jl"... int
@use GeometryBasics: Vec2
@use Colors: RGBA, red, green, blue, alpha, Colorant, N0f8
@use Skia
@use "./Geometric"...
@use "./Specific"...

# Convert color to Skia's ARGB format (0xAARRGGBB)
skia_argb(c::Colorant) = begin
  c = convert(RGBA{N0f8}, c)
  UInt32(reinterpret(UInt8, alpha(c))) << 24 |
  UInt32(reinterpret(UInt8, red(c))) << 16 |
  UInt32(reinterpret(UInt8, green(c))) << 8 |
  UInt32(reinterpret(UInt8, blue(c)))
end

# Draw a (possibly rounded) rectangle with fill and/or stroke
function draw_rect(canvas, x, y, w, h, r; background=nothing, color=nothing, stroke_width=0)
  path = Skia.sk_path_new()
  rect = Ref(Skia.sk_rect_t(Float32(int(x)), Float32(int(y)), Float32(int(x+w)), Float32(int(y+h))))
  GC.@preserve rect begin
    Skia.sk_path_add_rounded_rect(path, pointer_from_objref(rect), Float32(int(r)), Float32(int(r)), Skia.SK_PATH_DIRECTION_CW)
  end
  if !isnothing(background)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, skia_argb(background))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0)) # Fill
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end
  if !isnothing(color) && stroke_width > 0
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, skia_argb(color))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_paint_set_stroke_width(paint, Float32(int(stroke_width)))
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end
  Skia.sk_path_delete(path)
end

# Draw text at a position
function draw_text(canvas, x, y, font::SkiaFont, color::Colorant, str::String)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, skia_argb(color))
  Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0))
  blob = Skia.sk_textblob_make_from_string(str, font.raw, Skia.SK_TEXT_ENCODING_UTF8)
  Skia.sk_canvas_draw_text_blob(canvas, blob, Float32(int(x)), Float32(int(y)), paint)
  Skia.sk_paint_delete(paint)
end

"Render a draw function to a PNG file. `f(canvas, size, args...)` is called to draw."
function save_png(f::Function, path::AbstractString, size, args...; scale=(2.0, 2.0))
  (scalex, scaley) = scale
  x, y = int.(size)
  scaledx = round(Int, x*scalex)
  scaledy = round(Int, y*scaley)
  info = Ref(Skia.sk_image_info_t(C_NULL, Skia.sk_color_type_t(4), Skia.sk_alpha_type_t(1), scaledx, scaledy))
  GC.@preserve info begin
    surface = Skia.sk_surface_make_raster_n32_premul(pointer_from_objref(info), C_NULL)
    surface == C_NULL && error("Failed to create Skia surface ($(scaledx)x$(scaledy))")
    canvas = Skia.sk_surface_get_canvas(surface)
    Skia.sk_canvas_scale(canvas, Float32(scalex), Float32(scaley))
    invokelatest(f, canvas, size, args...)
    image = Skia.sk_surface_make_image_snapshot(surface)
    data = Skia.sk_encode_png(C_NULL, image, Int32(6))
    n = Skia.sk_data_get_size(data)
    ptr = Skia.sk_data_get_data(data)
    write(path, unsafe_wrap(Array, Ptr{UInt8}(ptr), n))
    Skia.sk_data_unref(data)
    Skia.sk_image_unref(image)
    Skia.sk_surface_unref(surface)
  end
  path
end

draw_ui(ctx, size, ui::ConcreteRect) = begin
  (;background, border, radius) = ui.from
  bw = border.top.width
  tl = ui.origin .+ bw/2
  sz = ui.size .- bw
  draw_rect(ctx, tl[1], tl[2], sz[1], sz[2], radius.tl,
            background=background.color,
            color=border.top.color,
            stroke_width=bw)
  for child in ui.children
    draw_ui(ctx, child.size, child)
  end
end

draw_ui(ctx, _, ui::ConcreteText) = begin
  f = SkiaFont(ui.from.family, ui.from.size)
  for (i, line) in enumerate(ui.lines)
    y = ui.top + ui.from.size * i
    draw_text(ctx, ui.left, y, f, ui.from.color, String(line))
  end
end

"Resolve a GeometricUI scene at the given size and save it as a PNG"
save_scene(path::AbstractString, scene::Container, size) =
  save_png(draw_ui, path, size, describe(scene, size))

export save_png, draw_ui, save_scene
