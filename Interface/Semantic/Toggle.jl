@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe theme scale handled integrate inputs
@use "../draw" draw cursor
@use Colors: @colorant_str

@def mutable struct Toggle <: SemanticUI
  on::Bool = false
end

describe(t::Toggle) = begin
  k = scale(theme(t))
  Row(width(34px * k), height(20px * k), radius(10px * k),
      background(t.on ? theme(t).accent : theme(t).track))
end

cursor(::Toggle) = :hand

onkey(t::Toggle, ::KeyPress{Keys.mouse_left}) = (t.on = !t.on; handled)

draw(ctx, size, ui::ConcreteRect, t::Toggle) = begin
  k = scale(theme(t))
  inset = 2px * k
  r = ui.height / 2 - inset
  cy = ui.top + inset
  cx = t.on ? ui.left + ui.width - inset - 2r : ui.left + inset
  rounded_rectangle(ctx, cx, cy, 2r, 2r, r, background=theme(t).on_accent)
end

"Whether the switch is on"
integrate(t::Toggle) = t.on

# What `describe` reads, so that it only runs again when one of these changes
inputs(t::Toggle) = (t.on,)

export Toggle
