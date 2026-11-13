@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe theme inputs
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
  color::Colorant = theme().text   # the theme's text colour, where the icon is made
  size::px = 16px
end

Icon(name::String; kwargs...) = Icon(;name=name, kwargs...)

# An icon keeps its size when its row runs out of room. Squeezed, it would vanish.
describe(icon::Icon) = Box(width(min=icon.size, preferred=icon.size), height(min=icon.size, preferred=icon.size))

draw(ctx, size, ui::ConcreteRect, icon::Icon) = begin
  data = load_icon(icon.name)
  render_svg(ctx, ui, data.paths, data.viewbox, icon.color)
end

# What `describe` reads, so that it only runs again when one of these changes
inputs(i::Icon) = (i.name, i.color, i.size)

export Icon
