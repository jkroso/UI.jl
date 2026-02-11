@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe
@use "../draw" draw
@use Colors: Colorant, RGBA, N0f8, @colorant_str, red, green, blue, alpha
@use Skia

const black = colorant"black"

@def struct SVGPath
  d::String = ""
  evenodd::Bool = false
end

@def mutable struct SVG <: SemanticUI
  node::Any = nothing
  paths::Vector{SVGPath} = SVGPath[]
  viewbox::NTuple{4,Float32} = (0f0, 0f0, 16f0, 16f0)
  color::Colorant = black
  width::px = 16px
  height::px = 16px
end

"Create an SVG from a DOM.jl Container{:svg} node"
SVG(node; kwargs...) = begin
  paths = SVGPath[]
  vb = (0f0, 0f0, 16f0, 16f0)
  if node !== nothing
    vb_str = get(node.attrs, :viewBox, "0 0 16 16")
    parts = split(vb_str)
    vb = (parse(Float32, parts[1]), parse(Float32, parts[2]),
          parse(Float32, parts[3]), parse(Float32, parts[4]))
    for child in node.children
      hasproperty(child, :attrs) || continue
      d = get(child.attrs, :d, nothing)
      d === nothing && continue
      eo = get(child.attrs, :rule, "") == "evenodd"
      push!(paths, SVGPath(d=d, evenodd=eo))
    end
  end
  SVG(;node=node, paths=paths, viewbox=vb, kwargs...)
end

"Parse an SVG file and extract paths with fill-rule support"
parse_svg_file(filepath::String) = begin
  raw = read(filepath, String)
  paths = SVGPath[]
  vb = (0f0, 0f0, 16f0, 16f0)
  m = match(r"viewBox=\"([^\"]+)\"", raw)
  if m !== nothing
    parts = split(m.captures[1])
    vb = (parse(Float32, parts[1]), parse(Float32, parts[2]),
          parse(Float32, parts[3]), parse(Float32, parts[4]))
  end
  for m in eachmatch(r"<path\s+([^>]*)/?>"s, raw)
    attr_str = m.captures[1]
    dm = match(r"d=\"([^\"]+)\"", attr_str)
    dm === nothing && continue
    eo = occursin("fill-rule=\"evenodd\"", attr_str)
    push!(paths, SVGPath(d=dm.captures[1], evenodd=eo))
  end
  (paths=paths, viewbox=vb)
end

to_skia_color(c::Colorant) = begin
  c = convert(RGBA{N0f8}, c)
  UInt32(reinterpret(UInt8, alpha(c))) << 24 |
  UInt32(reinterpret(UInt8, blue(c))) << 16 |
  UInt32(reinterpret(UInt8, green(c))) << 8 |
  UInt32(reinterpret(UInt8, red(c)))
end

describe(svg::SVG) = Box(width(svg.width), height(svg.height))

"Render SVG paths onto a Skia canvas, scaled from viewbox to target rect"
render_svg(ctx, ui::ConcreteRect, paths::Vector{SVGPath}, viewbox::NTuple{4,Float32}, color::Colorant) = begin
  isempty(paths) && return
  (vx, vy, vw, vh) = viewbox
  sx = Float32(int(ui.width)) / vw
  sy = Float32(int(ui.height)) / vh
  Skia.sk_canvas_save(ctx)
  Skia.sk_canvas_translate(ctx, Float32(int(ui.left)), Float32(int(ui.top)))
  Skia.sk_canvas_scale(ctx, sx, sy)
  (vx != 0 || vy != 0) && Skia.sk_canvas_translate(ctx, -vx, -vy)
  c = to_skia_color(color)
  for sp in paths
    p = Skia.sk_path_new()
    Skia.sk_path_parse_svg_string(p, sp.d)
    sp.evenodd && Skia.sk_path_set_filltype(p, Skia.SK_PATH_FILLTYPE_EVENODD)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_antialias(paint, true)
    Skia.sk_paint_set_color(paint, c)
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0))
    Skia.sk_canvas_draw_path(ctx, p, paint)
    Skia.sk_paint_delete(paint)
    Skia.sk_path_delete(p)
  end
  Skia.sk_canvas_restore(ctx)
end

draw(ctx, size, ui::ConcreteRect, svg::SVG) = render_svg(ctx, ui, svg.paths, svg.viewbox, svg.color)

export SVG, SVGPath, parse_svg_file, render_svg
