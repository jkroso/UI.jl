@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse int flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! add_child! focus theme scale handled window_of integrate
@use "../draw" draw ishovered cursor show_tooltip! redraw_in! rect inside
@use "./Icon" Icon
@use Colors: @colorant_str, HSV, RGB, RGBA, hex

@def mutable struct ColorPicker <: SemanticUI
  color::HSV = HSV(225, 0.8, 0.8)
  dragging::Symbol = :none
  copy::Any = nothing   # the copy button, kept so it remembers when it was clicked
end

"The button that copies the colour's hex code"
@def mutable struct CopyButton <: SemanticUI
  picker::Any = nothing
  copied::Float64 = 0.0                        # when it last copied, from time()
  glow::RGB{Float64} = RGB(0.0, 0.0, 0.0)      # the colour it copied then
end

copy_button(cp::ColorPicker) = begin
  cp.copy === nothing && (cp.copy = CopyButton(picker=cp))
  setfield!(cp.copy, :parent, cp)
  cp.copy
end

# After a click the whole button turns the colour it copied and fades back over
# GLOW seconds. The button keeps its size and its icon.
const GLOW = 0.6

since_copy(btn::CopyButton) = time() - btn.copied
"How much of the copied colour the button shows: 1 at the click, down to 0 after GLOW seconds"
strength(btn::CopyButton) = (t = since_copy(btn); 0 <= t < GLOW ? (1 - t / GLOW)^2 : 0.0)
"The colour that's `k` of the way from `a` to `b`"
blend(a, b, k) = (a = convert(RGB{Float64}, a); b = convert(RGB{Float64}, b);
                  RGB(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k))
"White or black, whichever shows better on `c`"
ink(c::RGB) = 0.299c.r + 0.587c.g + 0.114c.b > 0.6 ? RGB(0.0, 0.0, 0.0) : RGB(1.0, 1.0, 1.0)
hexcode(btn::CopyButton) = "#" * hex(convert(RGB, btn.picker.color))

describe(btn::CopyButton) = begin
  # Each frame of the glow asks for the next one
  since_copy(btn) < GLOW && redraw_in!(btn, 1/60)
  k = strength(btn)
  t = theme(btn)
  # The icon turns white or black with the colour, so that it still shows on it
  Box(padding(6px, 4px), radius(6px), Alignment.Center,
      background(blend(ishovered(btn) ? t.hover : t.surface, btn.glow, k)),
      border(1px, :solid, blend(t.line, btn.glow, k)),
    describe!(Icon("copy", size=14px, color=blend(t.dim, ink(btn.glow), k))))
end

cursor(::CopyButton) = :hand

"What the tooltip over the button says"
tip(btn::CopyButton) = Box(padding(8px, 6px),
  Box(Text((since_copy(btn) < GLOW ? "Copied " : "Copy ") * hexcode(btn), size=12pt, color=colorant"rgb(240,240,240)")))

show_tip!(btn::CopyButton, window) = begin
  r = rect(btn)
  r === nothing || show_tooltip!(window, tip(btn), r.left, r.top, r.width, r.height, placement=:top)
end

onmouse(btn::CopyButton, e::MouseMove) = show_tip!(btn, e.window)

onkey(btn::CopyButton, e::KeyPress{Keys.mouse_left}) = begin
  open(`pbcopy`, "w") do io
    print(io, hexcode(btn))
  end
  btn.copied = time()
  btn.glow = convert(RGB{Float64}, btn.picker.color)
  show_tip!(btn, e.window)
  handled
end

const SHADE_SIZE = 200px
const HUE_HEIGHT = 14px
const PICKER_PAD = 12px

describe(cp::ColorPicker) = begin
  rgb = convert(RGB, cp.color)
  Column(width(SHADE_SIZE + 2PICKER_PAD), padding(PICKER_PAD),
         radius(8px), border(1px, :solid, theme(cp).line),
         background(theme(cp).surface),
    Box(width(SHADE_SIZE), height(SHADE_SIZE)),
    Box(height(10px)),
    Box(width(SHADE_SIZE), height(HUE_HEIGHT)),
    Box(height(12px)),
    Row(width(SHADE_SIZE), height(28px * scale(theme(cp))), Alignment.Center,
      Box(width(24px * scale(theme(cp))), height(24px * scale(theme(cp))), radius(4px),
          background(rgb), border(1px, :solid, theme(cp).line)),
      Box(width(8px)),
      Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
          Text("#" * hex(rgb), size=12pt * scale(theme(cp)))),
      describe!(copy_button(cp))))
end

draw(ctx, size, ui::ConcreteRect, cp::ColorPicker) = begin
  shade = ui.children[1]
  hue_bar = ui.children[3]

  # Shade gradient (opaque 2D grid clipped to rounded rect)
  sr = 6px
  Skia.sk_canvas_save(ctx)
  clip = Skia.sk_path_new()
  shade_rect_ref = Ref(Skia.sk_rect_t(flt(shade.left), flt(shade.top),
                                       flt(shade.left + shade.width), flt(shade.top + shade.height)))
  Skia.sk_path_add_rounded_rect(clip, shade_rect_ref,
                                 flt(sr), flt(sr), Skia.SK_PATH_DIRECTION_CW)
  Skia.sk_canvas_clip_path_with_operation(ctx, clip, Skia.SK_CLIP_OP_INTERSECT, true)
  n = 64
  cw = shade.width / n
  ch = shade.height / n
  h = cp.color.h
  for ix in 0:n-1
    s = (ix + 0.5) / n
    for iy in 0:n-1
      v = 1.0 - (iy + 0.5) / n
      c = convert(RGB, HSV(h, s, v))
      rounded_rectangle(ctx, shade.left + ix * cw, shade.top + iy * ch,
                        cw + 1px, ch + 1px, 0px, background=c)
    end
  end
  Skia.sk_canvas_restore(ctx)
  Skia.sk_path_delete(clip)
  rounded_rectangle(ctx, shade.left, shade.top, shade.width, shade.height, sr,
                    color=theme(cp).line, stroke_width=1px)

  # Shade thumb
  sx = shade.left + cp.color.s * shade.width
  sy = shade.top + (1.0 - cp.color.v) * shade.height
  rounded_rectangle(ctx, sx - 7px, sy - 7px, 14px, 14px, 7px,
                    background=convert(RGB, cp.color),
                    color=colorant"white", stroke_width=2px)

  # Hue gradient — draw as a full-width pill, then overlay gradient strips inset from ends
  hr = hue_bar.height / 2
  rounded_rectangle(ctx, hue_bar.left, hue_bar.top, hue_bar.width, hue_bar.height,
                    hr, background=convert(RGB, HSV(0.0, 1.0, 1.0)))
  rounded_rectangle(ctx, hue_bar.left + hue_bar.width - hr * 2, hue_bar.top, hr * 2, hue_bar.height,
                    hr, background=convert(RGB, HSV(330.0, 1.0, 1.0)))
  inner_left = hue_bar.left + hr
  inner_w = hue_bar.width - hr * 2
  hn = 48
  hw = inner_w / hn
  for i in 0:hn-1
    h = (i + 0.5) / hn * 360.0
    c = convert(RGB, HSV(h, 1.0, 1.0))
    rounded_rectangle(ctx, inner_left + i * hw, hue_bar.top, hw + 1px, hue_bar.height, 0px,
                      background=c)
  end
  rounded_rectangle(ctx, hue_bar.left, hue_bar.top, hue_bar.width, hue_bar.height,
                    hr, color=theme(cp).line, stroke_width=1px)

  # Hue thumb
  hx = hue_bar.left + cp.color.h / 360.0 * hue_bar.width
  rounded_rectangle(ctx, hx - 3px, hue_bar.top - 2px, 6px, hue_bar.height + 4px, 3px,
                    background=colorant"white", color=colorant"rgb(100,100,100)", stroke_width=1.5px)
end

# Mouse events

"The rectangles of the square of shades and of the bar of hues, from the last layout"
areas(cp::ColorPicker) = (r = rect(cp); r === nothing ? nothing : (r.children[1], r.children[3]))

update_shade!(cp, shade, mx, my) = begin
  s = clamp(Float64((mx - shade.left) / shade.width), 0.0, 1.0)
  v = 1.0 - clamp(Float64((my - shade.top) / shade.height), 0.0, 1.0)
  cp.color = HSV(cp.color.h, s, v)
end

update_hue!(cp, bar, mx) = begin
  h = clamp(Float64((mx - bar.left) / bar.width), 0.0, 1.0) * 360.0
  cp.color = HSV(h, cp.color.s, cp.color.v)
end

# A crosshair over the square of shades and the bar of hues, where a click picks a colour
cursor(cp::ColorPicker) = begin
  found, w = areas(cp), window_of(cp)
  (found === nothing || w === nothing) && return nothing
  any(area -> inside(area, (w.mouse[1], w.mouse[2])), found) ? :crosshair : nothing
end

onkey(cp::ColorPicker, e::KeyPress{Keys.mouse_left}) = begin
  focus(cp)
  found = areas(cp)
  found === nothing && return handled
  shade, bar = found
  mx, my = e.window.mouse
  if inside(shade, (mx, my))
    cp.dragging = :shade
    update_shade!(cp, shade, mx, my)
  elseif inside(bar, (mx, my))
    cp.dragging = :hue
    update_hue!(cp, bar, mx)
  end
  handled
end

onmouse(cp::ColorPicker, e::MouseMove) = begin
  cp.dragging == :none && return
  !(Keys.mouse_left in e.window.keys) && (cp.dragging = :none; return)
  found = areas(cp)
  found === nothing && return
  mx, my = e.position
  cp.dragging == :shade ? update_shade!(cp, found[1], mx, my) : update_hue!(cp, found[2], mx)
  handled   # the drag is the picker's, so the nodes above don't act on it too
end

"The colour that's picked"
integrate(cp::ColorPicker) = cp.color

export ColorPicker
