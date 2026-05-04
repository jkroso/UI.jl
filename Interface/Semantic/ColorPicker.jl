@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse int flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! add_child! focus
@use "../draw" draw
@use "./Button" Button
@use "./Icon" Icon
@use Colors: @colorant_str, HSV, RGB, hex

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
end

@def mutable struct CopyButton <: SemanticUI
  picker::Any = nothing
end

describe(btn::CopyButton) = describe!(btn.firstchild)

onkey(btn::CopyButton, ::KeyPress{Keys.mouse_left}) = begin
  hex_str = "#" * hex(convert(RGB, btn.picker.color))
  open(`pbcopy`, "w") do io
    print(io, hex_str)
  end
end

const SHADE_SIZE = 200px
const HUE_HEIGHT = 14px
const PICKER_PAD = 12px

describe(cp::ColorPicker) = begin
  rgb = convert(RGB, cp.color)
  copy_btn = CopyButton(picker=cp)
  add_child!(copy_btn, Button(Icon("copy", size=14px, color=colorant"rgb(140,140,140)")))
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
      describe!(copy_btn)))
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
