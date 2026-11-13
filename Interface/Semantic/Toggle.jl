@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe theme scale handled integrate
@use "../draw" draw cursor
@use Colors: @colorant_str

@def mutable struct Toggle <: SemanticUI
  on::Bool = false
end

describe(t::Toggle) =
  Row(width(44px * scale(theme(t))), height(24px * scale(theme(t))), radius(12px * scale(theme(t))),
      background(t.on ? theme(t).accent : theme(t).track))

cursor(::Toggle) = :hand

onkey(t::Toggle, ::KeyPress{Keys.mouse_left}) = (t.on = !t.on; handled)

draw(ctx, size, ui::ConcreteRect, t::Toggle) = begin
  k = scale(theme(t))
  r = 9px * k
  cy = ui.top + ui.height / 2 - r
  cx = t.on ? ui.left + ui.width - 3px * k - 2r : ui.left + 3px * k
  rounded_rectangle(ctx, cx, cy, 2r, 2r, r, background=theme(t).on_accent)
end

"Whether the switch is on"
integrate(t::Toggle) = t.on

export Toggle
