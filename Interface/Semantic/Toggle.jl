@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe
@use "../draw" draw
@use Colors: @colorant_str

@def mutable struct Toggle <: SemanticUI
  on::Bool = false
end

describe(t::Toggle) =
  Row(width(44px), height(24px), radius(12px),
      background(t.on ? colorant"rgb(59,130,246)" : colorant"rgb(200,200,200)"))

onkey(t::Toggle, ::KeyPress{Keys.mouse_left}) = (t.on = !t.on)

draw(ctx, size, ui::ConcreteRect, t::Toggle) = begin
  r = 9px
  cy = ui.top + ui.height / 2 - r
  cx = t.on ? ui.left + ui.width - 3px - 2r : ui.left + 3px
  rounded_rectangle(ctx, cx, cy, 2r, 2r, r, background=colorant"white")
end

export Toggle
