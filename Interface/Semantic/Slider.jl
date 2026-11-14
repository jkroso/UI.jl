@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle sk_color
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse int flt
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"... text_width
@use "../abstract" SemanticUI WrapMode describe focus theme scale handled integrate inputs sized carry! step_animation ease
@use "../draw" draw rect cursor redraw_in!
@use Colors: @colorant_str, RGB, RGBA
@use Skia

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
  # Where the thumb was, as a fraction of the track, when a click or a key last moved the
  # slider. The thumb glides from there. `glided` is how far, from 0 to 1, and `stepped` is
  # when it last moved. A drag moves it with the mouse.
  was::Float64 = 0.0
  glided::Float64 = 1.0
  stepped::Float64 = 0.0
end

# These are the sizes when the theme's text has its usual size. `scale` makes them fit other sizes.
const TRACK_H = 4px
const THUMB_R = 9px
const MARK_GAP = 7px   # the least space between two ticks
const TICK_W = 1px     # of the tick under the track at each detent
const TICK_H = 4px
const TICK_TOP = 7px   # from the middle of the track to the top of a tick
# The thumb's shadow is soft and falls a little below it, as if the light were above
const SHADOW = RGBA(0.16, 0.1, 0.03, 0.35)
const SHADOW_BLUR = 2.5px
const SHADOW_DROP = 1px
const EDGE = RGBA(0.2, 0.15, 0.05, 0.12)   # the thin line round the thumb
# The thumb is near white on a light page and on a dark one, as a Mac's is, so it stands out from both
const KNOB = RGB(1.0, 0.995, 0.975)
const GLIDE = 0.24   # seconds the thumb takes to glide to a value it's clicked to

"The text a slider shows for the value `v`"
shown(s::Slider, v=s.value) = string(s.format(v))

describe(s::Slider) = begin
  k = scale(theme(s))
  # While the thumb glides, each frame moves it on and asks for the next one
  if s.glided < 1
    s.glided, s.stepped = step_animation(s.glided, s.stepped, GLIDE)
    redraw_in!(s, 1/60)
  end
  # A thin track, in the colour of a rule. What's filled is drawn over it.
  track = Box(width(grow=GrowType.Grow), height(TRACK_H * k), radius(TRACK_H / 2 * k), background(theme(s).line))
  s.format === nothing && return Row(width(grow=GrowType.Grow), height(24px * k), track)
  text = Text(shown(s), size=sized(13pt, theme(s)), wrap=WrapMode.none)
  # Room for its widest value, so the slider keeps its length while the text changes
  room = maximum(v -> text_width(text, shown(s, v)), (s.min, s.max, s.value))
  Row(width(grow=GrowType.Grow), height(24px * k), child_gap=(THUMB_R + 8px) * k, track,
    Row(width(room), justify=Alignment.End, text))
end

fraction(s::Slider) = clamp((s.value - s.min) / (s.max - s.min), 0.0, 1.0)

"Where the thumb shows, as a fraction of the track: on its way to the value while it glides"
shown_fraction(s::Slider) = s.glided >= 1 ? fraction(s) : s.was + (fraction(s) - s.was) * ease(s.glided)

"The detent nearest to `v`, or `v` itself when the slider has none"
detent(s::Slider, v) = s.step > 0 ? clamp(s.min + round((v - s.min) / s.step) * s.step, s.min, s.max) : clamp(v, s.min, s.max)

"""
Move the slider to `v`, or to the detent nearest to it. `onchange` is called if that's a
new value. With `glide`, the thumb glides there from where it shows, and without it, it
jumps there, as it does under the mouse in a drag.
"""
move!(s::Slider, v; glide=false) = begin
  v = detent(s, v)
  v == s.value && return
  s.was, s.glided, s.stepped = glide ? (shown_fraction(s), 0.0, time()) : (0.0, 1.0, 0.0)
  s.value = v
  s.onchange(s)
end

"Where the last layout put the slider's track, or `nothing` before its first frame"
track(s::Slider) = (r = rect(s); r === nothing ? nothing : r.children[1])

update_from_mouse!(s::Slider, mouse_x::px, t=track(s); glide=false) = begin
  t === nothing && return
  frac = clamp(Float64((mouse_x - t.left) / t.width), 0.0, 1.0)
  move!(s, s.min + frac * (s.max - s.min); glide)
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
  t !== nothing && t.left - r <= x <= t.left + t.width + r && update_from_mouse!(s, x, t, glide=true)
  handled
end

onkey(s::Slider, ::KeyPress{Keys.left}) = move!(s, s.value - step(s), glide=true)
onkey(s::Slider, ::KeyPress{Keys.right}) = move!(s, s.value + step(s), glide=true)

# A drag is the slider's, so the nodes above don't act on it too
onmouse(s::Slider, e::MouseMove) =
  Keys.mouse_left in e.window.keys ? (update_from_mouse!(s, e.position[1]); handled) : nothing

"""
A slider draws like a Mac's: the part of the track up to the value in the
accent colour, a tick under the track at each detent, and a round white thumb
with a soft shadow under it.
"""
draw(ctx, size, ui::ConcreteRect, s::Slider) = begin
  t = theme(s)
  track = ui.children[1]
  k = scale(t)
  middle = track.top + track.height / 2
  fill_w = track.width * shown_fraction(s)
  fill_w > 0px && rounded_rectangle(ctx, track.left, track.top, fill_w, track.height, track.height / 2, background=t.accent)
  # A tick under the track at each detent, when they aren't too close together to tell apart
  stops = s.step > 0 ? floor(Int, (s.max - s.min) / s.step + 1e-9) : 0
  if stops > 0 && track.width / stops >= MARK_GAP * k
    for i in 0:stops
      x = track.left + track.width * (i * s.step / (s.max - s.min))
      rounded_rectangle(ctx, x - TICK_W * k / 2, middle + TICK_TOP * k, TICK_W * k, TICK_H * k, TICK_W * k / 2, background=t.track)
    end
  end
  r = THUMB_R * k
  x = track.left + fill_w
  shadow(ctx, x, middle + SHADOW_DROP * k, r - 0.5px * k, SHADOW_BLUR * k)
  rounded_rectangle(ctx, x - r, middle - r, 2r, 2r, r, background=KNOB)
  rounded_rectangle(ctx, x - r, middle - r, 2r, 2r, r, color=EDGE, stroke_width=1)
end

"A soft shadow of a circle of radius `r` around (x, y)"
shadow(ctx, x, y, r, blur) = begin
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(SHADOW))
  # A blur fades out over 3 sigma, and sigma is half of the blur
  mask = Skia.sk_maskfilter_new_blur_with_flags(Skia.SK_BLUR_STYLE_NORMAL, flt(blur / 2), true)
  Skia.sk_paint_set_maskfilter(paint, mask)
  Skia.sk_canvas_draw_circle(ctx, flt(x), flt(y), flt(r), paint)
  Skia.sk_maskfilter_unref(mask)
  Skia.sk_paint_delete(paint)
end

"The value the slider is at"
integrate(s::Slider) = s.value

# What `describe` reads, so that it only runs again when one of these changes
inputs(s::Slider) = (s.value, s.min, s.max, s.format, s.glided)

# A slider made again in place of this one glides on from where it was
carry!(new::Slider, old::Slider) = begin
  new.was, new.glided, new.stepped = old.was, old.glided, old.stepped
  new
end

export Slider
