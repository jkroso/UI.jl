@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse int
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"... text_width
@use "../abstract" SemanticUI WrapMode describe focus theme scale handled integrate inputs
@use "../draw" draw rect cursor
@use Colors: @colorant_str

@def mutable struct Slider <: SemanticUI
  value::Float64 = 0.5
  min::Float64 = 0.0
  max::Float64 = 1.0
  # Called after the mouse or an arrow key changes `value`
  onchange::Function = slider -> nothing
  # Give it a function, and the slider shows what the function makes of `value` as text on its right,
  # e.g. `format=v -> round(Int, v)`
  format::Union{Nothing,Function} = nothing
  # The gap between its detents: the values it stops at, counted from `min`. With `step=1` and
  # `min=11` it stops at 11, 12, 13 and so on. 0 lets it stop anywhere.
  step::Float64 = 0.0
end

# These are the sizes when the theme's text has its usual size. `scale` makes them fit other sizes.
const THUMB_R = 8px
const MARK_R = 1px     # of the dot that marks a detent
const MARK_GAP = 7px   # the least space between two of those dots

"The text a slider shows for the value `v`"
shown(s::Slider, v=s.value) = string(s.format(v))

describe(s::Slider) = begin
  k = scale(theme(s))
  track = Box(width(grow=GrowType.Grow), height(6px * k), radius(3px * k), background(theme(s).track))
  s.format === nothing && return Row(width(grow=GrowType.Grow), height(24px * k), track)
  text = Text(shown(s), size=13pt * k, wrap=WrapMode.none)
  # Room for its widest value, so the slider keeps its length while the text changes
  room = maximum(v -> text_width(text, shown(s, v)), (s.min, s.max, s.value))
  Row(width(grow=GrowType.Grow), height(24px * k), child_gap=(THUMB_R + 8px) * k, track,
    Row(width(room), justify=Alignment.End, text))
end

fraction(s::Slider) = clamp((s.value - s.min) / (s.max - s.min), 0.0, 1.0)

"The detent nearest to `v`, or `v` itself when the slider has none"
detent(s::Slider, v) = s.step > 0 ? clamp(s.min + round((v - s.min) / s.step) * s.step, s.min, s.max) : clamp(v, s.min, s.max)

"Move the slider to `v`, or to the detent nearest to it. `onchange` is called if that's a new value."
move!(s::Slider, v) = begin
  v = detent(s, v)
  v == s.value && return
  s.value = v
  s.onchange(s)
end

"Where the last layout put the slider's track, or `nothing` before its first frame"
track(s::Slider) = (r = rect(s); r === nothing ? nothing : r.children[1])

update_from_mouse!(s::Slider, mouse_x::px, t=track(s)) = begin
  t === nothing && return
  frac = clamp(Float64((mouse_x - t.left) / t.width), 0.0, 1.0)
  move!(s, s.min + frac * (s.max - s.min))
end

"How far an arrow key moves it: one detent, or a fiftieth of its length"
step(s::Slider) = s.step > 0 ? s.step : (s.max - s.min) * 0.02

cursor(::Slider) = :hand

onkey(s::Slider, e::KeyPress{Keys.mouse_left}) = begin
  focus(s)
  x = e.window.mouse[1]
  t = track(s)
  # A click on the text beside the slider only gives it the keyboard
  r = THUMB_R * scale(theme(s))
  t !== nothing && t.left - r <= x <= t.left + t.width + r && update_from_mouse!(s, x, t)
  handled
end

onkey(s::Slider, ::KeyPress{Keys.left}) = move!(s, s.value - step(s))
onkey(s::Slider, ::KeyPress{Keys.right}) = move!(s, s.value + step(s))

# A drag is the slider's, so the nodes above don't act on it too
onmouse(s::Slider, e::MouseMove) =
  Keys.mouse_left in e.window.keys ? (update_from_mouse!(s, e.position[1]); handled) : nothing

draw(ctx, size, ui::ConcreteRect, s::Slider) = begin
  track = ui.children[1]
  # filled portion
  fill_w = track.width * fraction(s)
  k = scale(theme(s))
  fill_w > 0px && rounded_rectangle(ctx, track.left, track.top, fill_w, track.height, track.height / 2,
                                     background=theme(s).accent)
  # A dot in the track at each detent, when they aren't too close together to tell apart
  stops = s.step > 0 ? floor(Int, (s.max - s.min) / s.step + 1e-9) : 0
  if stops > 0 && track.width / stops >= MARK_GAP * k
    r = MARK_R * k
    for i in 0:stops
      x = track.left + clamp(track.width * (i * s.step / (s.max - s.min)), 2r, track.width - 2r)
      rounded_rectangle(ctx, x - r, track.top + track.height / 2 - r, 2r, 2r, r, background=theme(s).on_accent)
    end
  end
  # thumb
  thumb_r = THUMB_R * k
  thumb_x = track.left + fill_w - thumb_r
  thumb_y = ui.top + ui.height / 2 - thumb_r
  rounded_rectangle(ctx, thumb_x, thumb_y, 2thumb_r, 2thumb_r, thumb_r,
                    background=theme(s).accent)
  inner_r = 4px * k
  rounded_rectangle(ctx, thumb_x + thumb_r - inner_r, thumb_y + thumb_r - inner_r,
                    2inner_r, 2inner_r, inner_r, background=theme(s).on_accent)
end

"The value the slider is at"
integrate(s::Slider) = s.value

# What `describe` reads, so that it only runs again when one of these changes
inputs(s::Slider) = (s.value, s.min, s.max, s.format)

export Slider
