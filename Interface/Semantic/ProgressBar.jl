@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe
@use "../draw" draw
@use Colors: @colorant_str, parse, Colorant

@def mutable struct ProgressBar <: SemanticUI
  value::Float64 = 0.0
  color::Colorant = colorant"steelblue"
end

describe(p::ProgressBar) =
  Row(width(grow=GrowType.Grow), height(12px),
    radius(6px),
    background(colorant"rgb(230,230,230)"))

draw(ctx, size, ui::ConcreteRect, p::ProgressBar) = begin
  frac = clamp(p.value, 0.0, 1.0)
  fill_w = ui.width * frac
  fill_w > 1px || return
  rounded_rectangle(ctx, ui.left, ui.top, fill_w, ui.height, 6px,
                    background=p.color)
end

export ProgressBar
