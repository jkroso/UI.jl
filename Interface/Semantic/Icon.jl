@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe
@use "../draw" draw
@use "./SVG" SVG SVGPath parse_svg_file render_svg
@use Colors: Colorant, @colorant_str

const black = colorant"black"
const icons_dir = normpath(joinpath(@__DIR__(), "../../Icons"))
const icon_cache = Dict{String, NamedTuple{(:paths, :viewbox), Tuple{Vector{SVGPath}, NTuple{4,Float32}}}}()

load_icon(name::String) = get!(icon_cache, name) do
  parse_svg_file(joinpath(icons_dir, name * ".svg"))
end

@def mutable struct Icon <: SemanticUI
  name::String = ""
  color::Colorant = black
  size::px = 16px
end

describe(icon::Icon) = Box(width(icon.size), height(icon.size))

draw(ctx, size, ui::ConcreteRect, icon::Icon) = begin
  data = load_icon(icon.name)
  render_svg(ctx, ui, data.paths, data.viewbox, icon.color)
end

export Icon
