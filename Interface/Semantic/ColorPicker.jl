@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse int flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! add_child! focus
@use "../draw" draw ishovered cursor show_tooltip! redraw_in!
@use "./Icon" Icon
@use Colors: @colorant_str, HSV, RGB, RGBA, hex, weighted_color_mean

@def mutable struct ColorPicker <: SemanticUI
  color::HSV = HSV(225, 0.8, 0.8)
  shade_left::px = 0px
  shade_top::px = 0px
  shade_size::px = 0px
  hue_left::px = 0px
  hue_top::px = 0px
  hue_width::px = 0px
  hue_height::px = 0px
  dragging::Symbol = :none
  copy::Any = nothing   # the copy button, kept so it remembers when it was clicked
end

"The button that copies the colour's hex code"
@def mutable struct CopyButton <: SemanticUI
  picker::Any = nothing
  copied::Float64 = 0.0                        # when it last copied, from time()
  rect::NTuple{4,px} = (0px, 0px, 0px, 0px)    # where it was last drawn, to put its tooltip over it
end

copy_button(cp::ColorPicker) = begin
  cp.copy === nothing && (cp.copy = CopyButton(picker=cp))
  setfield!(cp.copy, :parent, cp)
  cp.copy
end

# After a click the button shows a tick for TICK seconds, and a ring spreads out
# from it and fades for RING seconds
const TICK = 0.6
const RING = 0.3
const GREEN = colorant"rgb(22,163,74)"
const PALE_GREEN = colorant"rgb(220,252,231)"

since_copy(btn::CopyButton) = time() - btn.copied
hexcode(btn::CopyButton) = "#" * hex(convert(RGB, btn.picker.color))

describe(btn::CopyButton) = begin
  t = since_copy(btn)
  ticked = t < TICK
  # Each frame of the ring asks for the next one, and the tick asks for the frame that takes it away
  t < RING ? redraw_in!(btn, 1/60) : ticked && redraw_in!(btn, TICK - t)
  base = ishovered(btn) ? colorant"rgb(243,244,246)" : colorant"white"
  fill = t < RING ? weighted_color_mean(1 - t / RING, PALE_GREEN, base) : base
  Box(padding(6px, 4px), radius(6px), background(fill), Alignment.Center,
      border(1px, :solid, ticked ? GREEN : colorant"rgb(229,231,235)"),
    describe!(Icon(ticked ? "check2" : "copy", size=14px, color=ticked ? GREEN : colorant"rgb(140,140,140)")))
end

cursor(::CopyButton) = :hand

"What the tooltip over the button says"
tip(btn::CopyButton) = Box(padding(8px, 6px),
  Box(Text((since_copy(btn) < TICK ? "Copied " : "Copy ") * hexcode(btn), size=12pt, color=colorant"rgb(240,240,240)")))

show_tip!(btn::CopyButton, window) = begin
  x, y, w, h = btn.rect
  w > 0px && show_tooltip!(window, tip(btn), x, y, w, h, placement=:top)
end

onmouse(btn::CopyButton, e::MouseMove) = show_tip!(btn, e.window)

onkey(btn::CopyButton, e::KeyPress{Keys.mouse_left}) = begin
  open(`pbcopy`, "w") do io
    print(io, hexcode(btn))
  end
  btn.copied = time()
  show_tip!(btn, e.window)
end

draw(ctx, size, ui::ConcreteRect, btn::CopyButton) = begin
  btn.rect = (ui.left, ui.top, ui.width, ui.height)
  t = since_copy(btn)
  t < RING || return
  # The ring grows from the edge of the button and fades as it goes
  k = t / RING
  grow = 7px * (1 - (1 - k)^3)
  rounded_rectangle(ctx, ui.left - grow, ui.top - grow, ui.width + 2grow, ui.height + 2grow, 6px + grow,
                    color=RGBA{Float64}(GREEN.r, GREEN.g, GREEN.b, 0.7 * (1 - k)), stroke_width=2px)
end

const SHADE_SIZE = 200px
const HUE_HEIGHT = 14px
const PICKER_PAD = 12px

describe(cp::ColorPicker) = begin
  rgb = convert(RGB, cp.color)
  Column(width(SHADE_SIZE + 2PICKER_PAD), padding(PICKER_PAD),
         radius(8px), border(1px, :solid, colorant"rgb(200,200,200)"),
         background(colorant"white"),
    Box(width(SHADE_SIZE), height(SHADE_SIZE)),
    Box(height(10px)),
    Box(width(SHADE_SIZE), height(HUE_HEIGHT)),
    Box(height(12px)),
    Row(width(SHADE_SIZE), height(28px), Alignment.Center,
      Box(width(24px), height(24px), radius(4px),
          background(rgb), border(1px, :solid, colorant"rgb(180,180,180)")),
      Box(width(8px)),
      Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
          Text("#" * hex(rgb), size=12pt, color=colorant"rgb(60,60,60)")),
      describe!(copy_button(cp))))
end

draw(ctx, size, ui::ConcreteRect, cp::ColorPicker) = begin
  shade = ui.children[1]
  hue_bar = ui.children[3]

  # Cache positions for mouse hit-testing
  cp.shade_left = shade.left
  cp.shade_top = shade.top
  cp.shade_size = shade.width
  cp.hue_left = hue_bar.left
  cp.hue_top = hue_bar.top
  cp.hue_width = hue_bar.width
  cp.hue_height = hue_bar.height

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
                    color=colorant"rgb(200,200,200)", stroke_width=1px)

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
                    hr, color=colorant"rgb(200,200,200)", stroke_width=1px)

  # Hue thumb
  hx = hue_bar.left + cp.color.h / 360.0 * hue_bar.width
  rounded_rectangle(ctx, hx - 3px, hue_bar.top - 2px, 6px, hue_bar.height + 4px, 3px,
                    background=colorant"white", color=colorant"rgb(100,100,100)", stroke_width=1.5px)
end

# Mouse events

update_shade!(cp, mx, my) = begin
  s = clamp(Float64((mx - cp.shade_left) / cp.shade_size), 0.0, 1.0)
  v = 1.0 - clamp(Float64((my - cp.shade_top) / cp.shade_size), 0.0, 1.0)
  cp.color = HSV(cp.color.h, s, v)
end

update_hue!(cp, mx) = begin
  h = clamp(Float64((mx - cp.hue_left) / cp.hue_width), 0.0, 1.0) * 360.0
  cp.color = HSV(h, cp.color.s, cp.color.v)
end

onkey(cp::ColorPicker, e::KeyPress{Keys.mouse_left}) = begin
  focus(cp)
  mx, my = e.window.mouse
  if mx >= cp.shade_left && mx <= cp.shade_left + cp.shade_size &&
     my >= cp.shade_top && my <= cp.shade_top + cp.shade_size
    cp.dragging = :shade
    update_shade!(cp, mx, my)
  elseif mx >= cp.hue_left && mx <= cp.hue_left + cp.hue_width &&
         my >= cp.hue_top && my <= cp.hue_top + cp.hue_height
    cp.dragging = :hue
    update_hue!(cp, mx)
  end
end

onmouse(cp::ColorPicker, e::MouseMove) = begin
  cp.dragging == :none && return
  !(Keys.mouse_left in e.window.keys) && (cp.dragging = :none; return)
  mx, my = e.position
  if cp.dragging == :shade
    update_shade!(cp, mx, my)
  elseif cp.dragging == :hue
    update_hue!(cp, mx)
  end
end

export ColorPicker
