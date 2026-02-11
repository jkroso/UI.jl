@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe focus
@use "../draw" draw
@use Colors: @colorant_str

@def mutable struct Slider <: SemanticUI
  value::Float64 = 0.5
  min::Float64 = 0.0
  max::Float64 = 1.0
  cached_left::px = 0px
  cached_width::px = 0px
end

describe(s::Slider) =
  Row(width(grow=GrowType.Grow), height(24px),
    Box(width(grow=GrowType.Grow), height(6px),
      radius(3px),
      background(colorant"rgb(220,220,220)")))

fraction(s::Slider) = clamp((s.value - s.min) / (s.max - s.min), 0.0, 1.0)

update_from_mouse!(s::Slider, mouse_x::px) = begin
  frac = clamp(Float64((mouse_x - s.cached_left) / s.cached_width), 0.0, 1.0)
  s.value = s.min + frac * (s.max - s.min)
end

step(s::Slider) = (s.max - s.min) * 0.02

onkey(s::Slider, e::KeyPress{Keys.mouse_left}) = begin
  focus(s)
  s.cached_left > 0px && update_from_mouse!(s, e.window.mouse[1])
end

onkey(s::Slider, ::KeyPress{Keys.left}) =
  (s.value = clamp(s.value - step(s), s.min, s.max))

onkey(s::Slider, ::KeyPress{Keys.right}) =
  (s.value = clamp(s.value + step(s), s.min, s.max))

onmouse(s::Slider, e::MouseMove) =
  Keys.mouse_left in e.window.keys && update_from_mouse!(s, e.position[1])

draw(ctx, size, ui::ConcreteRect, s::Slider) = begin
  # cache layout for mouse hit-testing
  s.cached_left = ui.left
  s.cached_width = ui.width
  # filled portion
  track = ui.children[1]
  track_y = track.top
  fill_w = ui.width * fraction(s)
  fill_w > 0px && rounded_rectangle(ctx, track.left, track_y, fill_w, track.height, 3px,
                                     background=colorant"rgb(59,130,246)")
  # thumb
  thumb_r = 8px
  thumb_x = ui.left + fill_w - thumb_r
  thumb_y = ui.top + ui.height / 2 - thumb_r
  rounded_rectangle(ctx, thumb_x, thumb_y, 2thumb_r, 2thumb_r, thumb_r,
                    background=colorant"rgb(59,130,246)")
  inner_r = 4px
  rounded_rectangle(ctx, thumb_x + thumb_r - inner_r, thumb_y + thumb_r - inner_r,
                    2inner_r, 2inner_r, inner_r, background=colorant"white")
end

export Slider
