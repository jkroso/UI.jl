@use "github.com/jkroso/Prospects.jl" Field @def
@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont font_metrics text_bounds sk_color
@use "github.com/jkroso/MiniFB.jl"... int KeyEvent flt onscroll onfiledrop
@use "github.com/jkroso/Font.jl" cap_height ["units" px absolute]
@use GeometryBasics: Vec2
@use Colors: @colorant_str, RGBA, Colorant, alpha, red, green, blue
@use Skia
@use GLFW
@use "./abstract" edits epoch ambient timed! theme with_theme Theme describe Root UITree SemanticUI GeometricUI ConcreteUI WrapMode mixin! window_of scale same semantic_parent handled sized
@use "./Geometric"...
@use "./Specific"... position!
@use "./fonts" skia_font
@use "./image" image_source

"Draw the lines a container puts between its children, centred in each gap"
function draw_between(ctx, ui::ConcreteRect)
  from = ui.from
  border = from.border.between
  (border.width > 0px && length(ui.children) > 1) || return
  for i in 2:length(ui.children)
    prev, child = ui.children[i-1], ui.children[i]
    if from isa Row
      x = (prev.left + prev.width + child.left) / 2
      stroke_line(ctx, (x, ui.top), (x, ui.top + ui.height), border)
    else
      y = (prev.top + prev.height + child.top) / 2
      stroke_line(ctx, (ui.left, y), (ui.left + ui.width, y), border)
    end
  end
end

"Run `f` with the canvas clipped to the given rect, then restore."
function with_clip(f, ctx, left::px, top::px, w::px, h::px)
  Skia.sk_canvas_save(ctx)
  rect = Ref(Skia.sk_rect_t(flt(left), flt(top), flt(left + w), flt(top + h)))
  Skia.sk_canvas_clip_rect_with_operation(ctx, rect, Skia.SK_CLIP_OP_INTERSECT, false)
  try
    f()
  finally
    Skia.sk_canvas_restore(ctx)
  end
end

"Run `f` with the canvas clipped to the given rect with its corners rounded by `r`, then restore."
function with_round_clip(f, ctx, left::px, top::px, w::px, h::px, r::px)
  Skia.sk_canvas_save(ctx)
  path = Skia.sk_path_new()
  rect = Ref(Skia.sk_rect_t(flt(left), flt(top), flt(left + w), flt(top + h)))
  Skia.sk_path_add_rounded_rect(path, rect, flt(r), flt(r), Skia.SK_PATH_DIRECTION_CW)
  Skia.sk_canvas_clip_path_with_operation(ctx, path, Skia.SK_CLIP_OP_INTERSECT, true)
  try
    f()
  finally
    Skia.sk_canvas_restore(ctx)
    Skia.sk_path_delete(path)
  end
end

"True iff drawing `ui` is a no-op given the canvas's current clip. Lets us
skip the entire subtree of an off-screen child without any rasterization
work. Outside a clip context this always returns false."
@inline function quick_reject(ctx, ui::ConcreteUI)
  l, t, r, b = shadow_reach(ui)
  rect = Ref(Skia.sk_rect_t(flt(ui.left - l), flt(ui.top - t),
                             flt(ui.left + ui.width + r), flt(ui.top + ui.height + b)))
  Skia.sk_canvas_quick_reject_rect(ctx, rect)
end

"How far a node's shadow reaches past its left, top, right and bottom edges"
shadow_reach(ui::ConcreteUI) = (0px, 0px, 0px, 0px)
shadow_reach(ui::ConcreteRect) = begin
  s = ui.from.shadow
  isempty(s) && return (0px, 0px, 0px, 0px)
  # A blur fades out over 3 sigma, and sigma is half of the blur
  grow = s.spread + 1.5s.blur
  (max(0px, grow - s.x), max(0px, grow - s.y), max(0px, grow + s.x), max(0px, grow + s.y))
end

"A Skia path around a node's shape: its slice if it's a Wedge, or its box with `grow` added to each side"
function outline(ui::ConcreteRect, grow=0px)
  from = ui.from
  from isa Wedge && return wedge_path(wedge_circle(ui)..., from.inner, from.outer, from.start, from.sweep)
  (;tl, tr, br, bl) = from.radius
  # Like CSS, a square corner stays square when the shadow spreads
  grown(r) = r > 0px ? max(0px, r + grow) : 0px
  box_path(ui.left - grow, ui.top - grow, ui.width + 2grow, ui.height + 2grow, grown(tl), grown(tr), grown(br), grown(bl))
end

"A Skia path around a box. Each corner has its own radius, in the order top left, top right, bottom right, bottom left."
function box_path(left, top, w, h, tl, tr, br, bl)
  p = Skia.sk_path_new()
  if tl == tr == br == bl
    rect = Ref(Skia.sk_rect_t(flt(left), flt(top), flt(left + w), flt(top + h)))
    Skia.sk_path_add_rounded_rect(p, rect, flt(tl), flt(tl), Skia.SK_PATH_DIRECTION_CW)
    return p
  end
  # A corner can't be rounder than half of the box's shorter side
  most = max(0px, min(w, h) / 2)
  tl, tr, br, bl = min(tl, most), min(tr, most), min(br, most), min(bl, most)
  right, bottom = left + w, top + h
  # A quarter circle of radius `r` round the middle of a corner. Skia measures angles clockwise from 3 o'clock.
  corner(cx, cy, r, from) = begin
    oval = Ref(Skia.sk_rect_t(flt(cx - r), flt(cy - r), flt(cx + r), flt(cy + r)))
    r > 0px ? Skia.sk_path_arc_to_with_oval(p, oval, Float32(from), 90f0, false) : Skia.sk_path_line_to(p, flt(cx), flt(cy))
  end
  Skia.sk_path_move_to(p, flt(left + tl), flt(top))
  corner(right - tr, top + tr, tr, -90)
  corner(right - br, bottom - br, br, 0)
  corner(left + bl, bottom - bl, bl, 90)
  corner(left + tl, top + tl, tl, 180)
  Skia.sk_path_close(p)
  p
end

"True when a box's four corners have one radius, which is the shape Skia draws quickest"
even(r::Radius) = r.tl == r.tr == r.br == r.bl

"Fill a Skia path with a colour"
function fill_path(ctx, p, color)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(color))
  Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0))
  Skia.sk_canvas_draw_path(ctx, p, paint)
  Skia.sk_paint_delete(paint)
end

"""
Draw a line along a Skia path in the style of a border's side: solid, dashed
or dotted, `width` wide. The line is centred on the path.
"""
function stroke_path(ctx, p, side::BorderSide, width=side.width)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(side.color))
  Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1))
  Skia.sk_paint_set_stroke_width(paint, flt(width))
  effect = C_NULL
  if side.style == BorderStyle.dashed
    effect = Skia.sk_path_effect_create_dash(Float32[3flt(width), 3flt(width)], Cint(2), 0f0)
  elseif side.style == BorderStyle.dotted
    # A round end on a dash with no length makes a dot as wide as the line
    Skia.sk_paint_set_stroke_cap(paint, Skia.SK_STROKE_CAP_ROUND)
    effect = Skia.sk_path_effect_create_dash(Float32[0f0, 2flt(width)], Cint(2), 0f0)
  end
  effect == C_NULL || Skia.sk_paint_set_path_effect(paint, effect)
  Skia.sk_canvas_draw_path(ctx, p, paint)
  effect == C_NULL || Skia.sk_path_effect_unref(effect)
  Skia.sk_paint_delete(paint)
end

"Draw a straight line in the style of a border's side. A double one is two thin lines with a gap between them."
function stroke_line(ctx, from, to, side::BorderSide)
  along(shift, width) = begin
    p = Skia.sk_path_new()
    # `shift` moves the line sideways: across a line that goes down, and down a line that goes across
    dx, dy = from[1] == to[1] ? (shift, 0px) : (0px, shift)
    Skia.sk_path_move_to(p, flt(from[1] + dx), flt(from[2] + dy))
    Skia.sk_path_line_to(p, flt(to[1] + dx), flt(to[2] + dy))
    stroke_path(ctx, p, side, width)
    Skia.sk_path_delete(p)
  end
  if side.style == BorderStyle.double
    along(-side.width / 3, side.width / 3)
    along(side.width / 3, side.width / 3)
  else
    along(0px, side.width)
  end
end

"""
Draw the shadow a node casts: its shape, moved, grown by `spread` and blurred.
The node's own shape is cut out of it, so a see-through background doesn't
show the shadow behind it.
"""
function draw_shadow(ctx, ui::ConcreteRect, s::Shadow)
  Skia.sk_canvas_save(ctx)
  shape = outline(ui)
  Skia.sk_canvas_clip_path_with_operation(ctx, shape, Skia.SK_CLIP_OP_DIFFERENCE, true)
  Skia.sk_path_delete(shape)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(s.color))
  blur = C_NULL
  if s.blur > 0px
    blur = Skia.sk_maskfilter_new_blur_with_flags(Skia.SK_BLUR_STYLE_NORMAL, flt(s.blur / 2), true)
    Skia.sk_paint_set_maskfilter(paint, blur)
  end
  cast = outline(ui, s.spread)
  Skia.sk_canvas_translate(ctx, flt(s.x), flt(s.y))
  Skia.sk_canvas_draw_path(ctx, cast, paint)
  Skia.sk_path_delete(cast)
  blur == C_NULL || Skia.sk_maskfilter_unref(blur)
  Skia.sk_paint_delete(paint)
  Skia.sk_canvas_restore(ctx)
end

"""
Where a Scroll's scrollbar track and thumb sit, or `nothing` when the content
fits and no scrollbar is needed.
"""
function scrollbar_geometry(ui::ConcreteRect, scroll::Scroll)
  viewport = ui.height
  content = scroll.content_height
  content > viewport || return nothing
  w = scroll.scrollbar_width
  margin = 4px
  track_x = ui.left + ui.width - w - scroll.scrollbar_inset
  track_y = ui.top + margin
  track_h = ui.height - 2margin
  thumb_h = max(24px, track_h * (viewport / content))
  range = max(1px, content - viewport)
  ratio = clamp(scroll.offset / range, 0.0, 1.0)
  thumb_y = track_y + (track_h - thumb_h) * ratio
  (x=track_x, y=track_y, width=w, height=track_h, thumb_y=thumb_y, thumb_h=thumb_h, range=range)
end

scrollbar_visible(scroll::Scroll) =
  scroll.scrollbar == ScrollbarMode.always ||
  (scroll.scrollbar == ScrollbarMode.hover && (scroll.hover || scroll.dragging))

"Scale a colour's opacity, keeping it within 0–1"
fade(c::Colorant, k) = RGBA(red(c), green(c), blue(c), clamp(alpha(c) * k, 0, 1))

function draw_scrollbar(ctx, ui::ConcreteRect, scroll::Scroll)
  scrollbar_visible(scroll) || return
  g = scrollbar_geometry(ui, scroll)
  g === nothing && return
  alpha(scroll.scrollbar_track) > 0 &&
    rounded_rectangle(ctx, g.x, g.y, g.width, g.height, g.width/2, background=scroll.scrollbar_track)
  k = scroll.dragging ? 1.6 : scroll.thumb_hover ? 1.3 : 1.0
  rounded_rectangle(ctx, g.x, g.thumb_y, g.width, g.thumb_h, g.width/2, background=fade(scroll.scrollbar_color, k))
end

"""
Borders are drawn inside the element's bounds, after its children so a child's
background can't cover them. When all four sides match they follow the corner
radii. Otherwise each side is drawn as its own straight edge. A side can be
`:solid`, `:dashed`, `:dotted` or `:double`.
"""
function draw_border(ctx, ui::ConcreteRect)
  (;border, radius) = ui.from
  sides = (border.top, border.right, border.bottom, border.left)
  all(isempty, sides) && return
  side = border.top
  if all(==(side), sides)
    bw = side.width
    # A line `width` wide that runs round the box `inset` from its edge
    ring(inset, width) = begin
      p = outline(ui, -inset)
      stroke_path(ctx, p, side, width)
      Skia.sk_path_delete(p)
    end
    if side.style == BorderStyle.double
      ring(bw / 6, bw / 3)
      ring(5bw / 6, bw / 3)
    elseif side.style == BorderStyle.solid && even(radius)
      rounded_rectangle(ctx, ui.origin .+ bw/2, ui.size .- bw, max(0px, radius.tl - bw/2), color=side.color, stroke_width=bw)
    else
      ring(bw / 2, bw)
    end
  else
    (;left, top, width, height) = ui
    edge(x, y, w, h, side) = begin
      isempty(side) && return
      side.style == BorderStyle.solid && return rounded_rectangle(ctx, x, y, w, h, 0px, background=side.color)
      # A line along the middle of the side
      w > h ? stroke_line(ctx, (x, y + h/2), (x + w, y + h/2), side) : stroke_line(ctx, (x + w/2, y), (x + w/2, y + h), side)
    end
    edge(left, top, width, border.top.width, border.top)
    edge(left, top + height - border.bottom.width, width, border.bottom.width, border.bottom)
    edge(left, top, border.left.width, height, border.left)
    edge(left + width - border.right.width, top, border.right.width, height, border.right)
  end
end

const sampling = Skia.sk_sampling_options_t(0, false, Skia.sk_cubic_resampler_t(0f0, 0f0),
                                            Skia.SK_FILTER_MODE_LINEAR, Skia.SK_MIPMAP_MODE_LINEAR)

"Draw an Image's pixels stretched over its box, clipped to its corner radius"
function draw_image(ctx, ui::ConcreteRect, img::Image)
  isempty(img.src) && return
  src = image_source(img.src)
  srcrect = Ref(Skia.sk_rect_t(0f0, 0f0, Float32(src.width), Float32(src.height)))
  dst = Ref(Skia.sk_rect_t(flt(ui.left), flt(ui.top), flt(ui.left + ui.width), flt(ui.top + ui.height)))
  opts = Ref(sampling)
  Skia.sk_canvas_save(ctx)
  (;tl, tr, br, bl) = img.radius
  if max(tl, tr, br, bl) > 0px
    p = outline(ui)
    Skia.sk_canvas_clip_path_with_operation(ctx, p, Skia.SK_CLIP_OP_INTERSECT, true)
    Skia.sk_path_delete(p)
  end
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_canvas_draw_image_rect(ctx, src.raw, srcrect, dst, opts, paint, Skia.SRC_RECT_CONSTRAINT_FAST)
  Skia.sk_paint_delete(paint)
  Skia.sk_canvas_restore(ctx)
end

"The centre of a Wedge's box and the radius of the biggest circle that fits in it"
wedge_circle(ui::ConcreteRect) = begin
  (;padding) = ui.from
  w, h = ui.width - padding.width, ui.height - padding.height
  (ui.left + padding.left + w/2, ui.top + padding.top + h/2, min(w, h)/2)
end

"A Skia path around a slice of a ring in a circle of radius `r`. `inner` and `outer` are fractions of `r`. Angles are clockwise from 12 o'clock."
function wedge_path(cx, cy, r, inner, outer, start, sweep)
  r0, r1 = inner * r, outer * r
  p = Skia.sk_path_new()
  oval(r) = Ref(Skia.sk_rect_t(flt(cx - r), flt(cy - r), flt(cx + r), flt(cy + r)))
  if sweep >= 360
    Skia.sk_path_add_circle(p, flt(cx), flt(cy), flt(r1), Skia.SK_PATH_DIRECTION_CW)
    r0 > 0px && Skia.sk_path_add_circle(p, flt(cx), flt(cy), flt(r0), Skia.SK_PATH_DIRECTION_CCW)
  else
    # Skia measures angles from 3 o'clock
    a, s = Float32(start - 90), Float32(sweep)
    Skia.sk_path_arc_to_with_oval(p, oval(r1), a, s, true)
    if r0 > 0px
      Skia.sk_path_arc_to_with_oval(p, oval(r0), a + s, -s, false)
    else
      Skia.sk_path_line_to(p, flt(cx), flt(cy))
    end
    Skia.sk_path_close(p)
  end
  p
end

function draw_wedge(ctx, ui::ConcreteRect, w::Wedge)
  p = outline(ui)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  if alpha(w.background.color) > 0
    Skia.sk_paint_set_color(paint, sk_color(w.background.color))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0))
    Skia.sk_canvas_draw_path(ctx, p, paint)
  end
  Skia.sk_paint_delete(paint)
  isempty(w.border.top) || stroke_path(ctx, p, w.border.top)
  Skia.sk_path_delete(p)
end

"True when `pos`, which is inside `ui`'s box, is on the shape that `from` draws there"
on_shape(from, ui, pos) = true
on_shape(w::Wedge, ui::ConcreteRect, (x, y)) = begin
  cx, cy, r = wedge_circle(ui)
  # As fractions of the radius, like `inner` and `outer`
  dx, dy = (x - cx) / r, (y - cy) / r
  w.inner <= hypot(dx, dy) <= w.outer || return false
  w.sweep >= 360 || mod(atand(dx, -dy) - w.start, 360) <= w.sweep
end

function draw_children(ctx, ui::ConcreteRect)
  for child in ui.children
    quick_reject(ctx, child) && continue
    draw(ctx, child.size, child)
  end
end

draw(ctx, size, ui::ConcreteRect) = begin
  from = ui.from
  (;background, radius) = from
  isempty(from.shadow) || draw_shadow(ctx, ui, from.shadow)
  if from isa Wedge
    draw_wedge(ctx, ui, from)
  elseif alpha(background.color) > 0
    if even(radius)
      rounded_rectangle(ctx, ui.origin, ui.size, radius.tl, background=background.color)
    else
      shape = outline(ui)
      fill_path(ctx, shape, background.color)
      Skia.sk_path_delete(shape)
    end
  end
  from isa Image && draw_image(ctx, ui, from)
  if from isa Scroll
    with_clip(() -> draw_children(ctx, ui), ctx, ui.left, ui.top, ui.width, ui.height)
  elseif from.clip
    with_clip(ctx, ui.left, ui.top, ui.width, ui.height) do
      draw_children(ctx, ui)
      draw_between(ctx, ui)
    end
  elseif from.clip_x
    # Cut off at the left and right edges only
    with_clip(ctx, ui.left, ui.top - 10000px, ui.width, ui.height + 20000px) do
      draw_children(ctx, ui)
      draw_between(ctx, ui)
    end
  else
    draw_children(ctx, ui)
    draw_between(ctx, ui)
  end
  from isa Wedge || draw_border(ctx, ui)
  from isa Scroll && draw_scrollbar(ctx, ui, from)
  from.from !== nothing && draw(ctx, size, ui, from.from)
end

draw(ctx, size, ui::ConcreteRect, source) = nothing

draw(ctx, _, ui::ConcreteText) = begin
  f = font(ui.from)
  caph = px(font_metrics(f).capHeight)                   # match Specific's layout sizing
  leading = absolute(ui.from.lineheight, ui.from.size)   # spacing between subsequent baselines
  align = ui.from.align
  for (i, line) in enumerate(ui.lines)
    s = String(line)
    x = ui.left
    if align != TextAlign.Left
      # Use Skia's tight visual bounds so glyphs with uneven side bearings
      # (e.g. "1") visually centre rather than centring their advance box.
      b = text_bounds(f, s)
      visual_w = px(b.right - b.left)
      slack = ui.width - visual_w
      offset = align == TextAlign.Center ? slack/2 : slack
      x += offset - px(b.left)
    end
    y = ui.top + caph + (i - 1) * leading
    text(ctx, (x, y), f, ui.from.color, s)
  end
end

"Offset all positions in a ConcreteUI tree"
offset!(ui::ConcreteRect, dx::px, dy::px) = begin
  ui.left += dx
  ui.top += dy
  for child in ui.children
    offset!(child, dx, dy)
  end
end
offset!(ui::ConcreteText, dx::px, dy::px) = begin
  ui.left += dx
  ui.top += dy
end

# --- popups ------------------------------------------------------------------
#
# A popup floats over the app: a menu, a tooltip, a list of suggestions. What it
# shows is an ordinary node. It's laid out, drawn and given events the way the
# app's own nodes are, so a component in a popup works as it does anywhere else.

@def mutable struct Popup
  key::Symbol = :popup
  content::Any = nothing                       # a semantic node, or a layout
  anchor::NTuple{4,px} = (0px, 0px, 0px, 0px)  # the rectangle it's put beside: left, top, width, height
  target::Any = nothing                        # the node that the anchor follows, or nothing for an anchor that stays where it is
  placement::Symbol = :below
  gap::px = 0px
  width::Union{Nothing,px} = nothing
  input::Bool = true
  onclose::Any = nothing
  theme::Theme = theme()
  scene::Union{Nothing,ConcreteRect} = nothing   # where its last layout put it
end

const _popups = Dict{UInt, Vector{Popup}}()

"The popups a window is showing, in the order they opened"
popups(w) = get(_popups, objectid(w), ())

"A length in px, from a plain number or from a length in any unit"
inpx(x) = x isa px ? x : x isa Union{Integer,AbstractFloat} ? px(x) : convert(px, x)

"An anchor as a rectangle: left, top, width, height. A place is a rectangle with no size."
box(r::ConcreteRect) = (r.left, r.top, r.width, r.height)
box(r::NTuple{4,Any}) = (inpx(r[1]), inpx(r[2]), inpx(r[3]), inpx(r[4]))
box(r::Union{Tuple{Any,Any},Vec2}) = (inpx(r[1]), inpx(r[2]), 0px, 0px)

"""
Show `content` floating over the app in `window`. `content` is a semantic node
or a layout. It gets clicks, mouse moves and key presses like any other node,
and key presses go to it before they go to the node that has the keyboard. A
click outside it, or Escape, closes it and calls `onclose()`.

`anchor` is what it's put beside: a place `(x, y)`, a rectangle
`(left, top, width, height)`, what `rect(node)` returns, or a node. Without one
it's put at the mouse. A popup beside a node follows the node when it moves, as
it does when the page it's on scrolls. It closes, and calls `onclose()`, when
the node goes out of sight. `placement` says where:

- `:below`: under the anchor, with their left edges in line. A menu goes here.
- `:bottom`, `:top`, `:left`, `:right`: on that side of the anchor, centred on it.

`width` lays it out that wide. Without it, it's as wide as its content.
`input=false` makes it something to look at only, like a tooltip: the mouse
goes through it and it never closes by itself. A window shows one popup for
each `key`, so a new one takes the place of the last one with its `key`.

    onkey(b::MoreButton, e::KeyPress{Keys.mouse_left}) = popup!(e.window, Settings(), anchor=rect(b), gap=4px)
"""
popup!(window, content; anchor=window.mouse, placement=:below, gap=0px, width=nothing, key=:popup, input=true, onclose=nothing,
       theme=theme()) = begin
  close_popup!(window, key)
  # A node of its own finds its window through a root, as the app's nodes do
  content isa UITree && content.parent === nothing && Root(content, window=window)
  target = anchor isa SemanticUI ? anchor : nothing
  if target !== nothing
    r = rect(target)
    anchor = r === nothing ? (0px, 0px) : r
  end
  popup = Popup(key=key, content=content, anchor=box(anchor), target=target, placement=placement, gap=gap, width=width,
                input=input, onclose=onclose, theme=theme)
  push!(get!(Vector{Popup}, _popups, objectid(window)), popup)
  popup
end

"Take away the popup that was shown with `key`. Its `onclose` isn't called: that's for when the user closes it."
close_popup!(window, key::Symbol=:popup) = begin
  list = get(_popups, objectid(window), nothing)
  list === nothing || filter!(p -> p.key != key, list)
  nothing
end

"Close a popup because the user clicked outside it or pressed Escape, and tell it so"
dismiss!(window, popup::Popup) = begin
  filter!(p -> p !== popup, _popups[objectid(window)])
  popup.onclose === nothing || popup.onclose()
  nothing
end

"True when the middle of `node`, which `r` is the rectangle of, is in sight: nothing covers it and it isn't scrolled away"
insight(scene::ConcreteRect, node, r::ConcreteRect) = begin
  hit = hittest(scene, Vec2{px}(r.left + r.width / 2, r.top + r.height / 2))
  while hit !== nothing
    (hit === node || same(hit, node)) && return true
    hit = semantic_parent(hit)
  end
  false
end

"""
Move each popup that's beside a node to where the node is in `scene`, the
layout of this frame. A popup whose node is gone or out of sight closes.
"""
follow!(w, scene::ConcreteRect) = begin
  tracked = [p for p in popups(w) if p.target !== nothing]
  isempty(tracked) && return
  id = objectid(w)
  for popup in tracked
    r = rect(popup.target)
    if r === nothing || !insight(scene, popup.target, r)
      dismiss!(w, popup)
      # What opened it may draw itself another way now that it's closed
      _soon[id] = 0.0
    else
      popup.anchor = box(r)
    end
  end
  # These rectangles were looked up before the popups were put in place, so look them up again when next asked
  delete!(_rects, id)
end

"Lay a popup out and put it beside its anchor, inside a window of `size`"
place!(popup::Popup, size) = begin
  geo = with_theme(() -> convert(GeometricUI, popup.content), popup.theme)
  ui = describe(geo, (something(popup.width, 9999px), 9999px))
  left, top, w, h = popup.anchor
  gap = popup.gap
  x, y = popup.placement == :below  ? (left, top + h + gap) :
         popup.placement == :bottom ? (left + w/2 - ui.width/2, top + h + gap) :
         popup.placement == :top    ? (left + w/2 - ui.width/2, top - ui.height - gap) :
         popup.placement == :right  ? (left + w + gap, top + h/2 - ui.height/2) :
         popup.placement == :left   ? (left - ui.width - gap, top + h/2 - ui.height/2) :
                                      error("unknown placement: $(popup.placement)")
  # One that's above or below its anchor moves in from the edge of the window
  popup.placement in (:below, :bottom, :top) && (x = clamp(x, min(x, 4px), max(4px, size[1] - ui.width - 4px)))
  # A menu that would run off the bottom of the window moves up
  popup.placement == :below && (y = clamp(y, min(y, 4px), max(4px, size[2] - ui.height - 4px)))
  offset!(ui, x, y)
  popup.scene = ui
end

"The popup that takes the mouse at `pos`: the one on top of those under it"
popup_at(w, pos) = begin
  for popup in Iterators.reverse(popups(w))
    popup.input && popup.scene !== nothing && inside(popup.scene, pos) && return popup
  end
  nothing
end

"The popup that key presses go to first: the last one opened that takes input"
key_popup(w) = begin
  for popup in Iterators.reverse(popups(w))
    popup.input && return popup
  end
  nothing
end

# --- menus -------------------------------------------------------------------

"""
A list of choices that floats over the app. `show_menu!` makes one. The mouse
or the up and down arrows highlight a choice, and a click or Return picks it.
"""
@def mutable struct MenuList <: SemanticUI
  items::Vector{String} = String[]
  onselect::Any = nothing
  item_height::px = 32px
  dividers::Bool = false
  lift::Float64 = 1.0
  families::Vector{String} = String[]   # the font of each item, like each font's own in a font picker. Empty uses the theme's.
  active::Int = 0          # the item that's highlighted, or 0
  by_mouse::Bool = false   # the mouse highlighted it, so it's plain again when the mouse leaves
end

"One choice in a `MenuList`"
@def mutable struct MenuRow <: SemanticUI
  list::Any = nothing
  index::Int = 0
end

"The item that shows as highlighted, or 0"
highlighted(list::MenuList) = list.by_mouse && !ishovered(list) ? 0 : list.active

describe(list::MenuList) = begin
  t = theme(list)
  # A faint shadow, so that the menu's own border still marks its edge. A bigger `lift` makes it darker, wider and lower.
  column = Column(width(grow=GrowType.Grow), radius(6px), background(t.surface), border(1px, :solid, t.line),
                  shadow(0px, 2px * list.lift, (5 + 5list.lift) * 1px, RGBA(0, 0, 0, clamp(0.05 + 0.05list.lift, 0, 0.5))))
  list.dividers && mixin!(column, border(1px, :solid, fade(t.line, 0.6), between=true)[:between])
  for i in eachindex(list.items)
    mixin!(column, MenuRow(list=list, index=i))
  end
  column
end

describe(row::MenuRow) = begin
  list = row.list
  t = theme(row)
  k = scale(t)
  inset = 4px * k   # between the highlight of an item and the edges of the item, the same on every side
  item = Row(width(grow=GrowType.Grow), height(grow=GrowType.Grow), radius(4px), padding(0px, 0px, 0px, 14px * k - inset),
             Box(offset_y=-1px * k, Text(list.items[row.index]; size=sized(13pt, t), wrap=WrapMode.none,
                                         family_of(list.families, row.index, t)...)))
  row.index == highlighted(list) && mixin!(item, background(t.select))
  Row(width(grow=GrowType.Grow), height(list.item_height), padding(inset), item)
end

"The font of item `i`, as a keyword for `Text`, when a list of fonts gives it one"
family_of(families, i, t) = i <= length(families) && !isempty(families[i]) ? (family=families[i],) : ()

"Pick item `i`: close the menu, then tell `onselect`"
choose!(list::MenuList, i::Int) = begin
  w = window_of(list)
  w === nothing || close_popup!(w, :menu)
  list.onselect === nothing || list.onselect(i)
  nothing
end

"Move the highlight up or down by one item. It goes round from the last item to the first."
step!(list::MenuList, by::Int) = begin
  n = length(list.items)
  n == 0 && return
  at = highlighted(list)
  list.active = at == 0 ? (by > 0 ? 1 : n) : mod1(at + by, n)
  list.by_mouse = false
  nothing
end

cursor(::MenuRow) = :hand
onmouse(row::MenuRow, ::MouseMove) = (row.list.active = row.index; row.list.by_mouse = true; nothing)
onkey(row::MenuRow, ::KeyPress{Keys.mouse_left}) = (choose!(row.list, row.index); handled)
onkey(list::MenuList, ::KeyPress{Keys.down}) = (step!(list, 1); handled)
onkey(list::MenuList, ::KeyPress{Keys.up}) = (step!(list, -1); handled)
onkey(list::MenuList, ::KeyPress{Keys.enter}) = (i = highlighted(list); i > 0 && choose!(list, i); handled)

"""
Show a floating menu in a window, with its top left corner at `(x, y)`. When an
item is picked, `onselect` is called with its place in `items`. It's called
with 0 when the menu closes with nothing picked: after a click outside it, or
Escape. The up and down arrows move the highlight and Return picks.

Its text is the size the theme asks for, so give it an `item_height` that
fits: 32px with the usual size. `dividers=true` draws a faint line between
each item and the next. `families` gives each item a font of its own, like
the font itself for each name in a font picker. `lift` is how high the menu seems to float: a bigger
number gives it a darker, wider shadow.

`under` is a node to hang the menu from, `gap` under its bottom edge, in place
of `(x, y)`. The menu then follows the node when it moves, as it does when the
page it's on scrolls, and closes when the node goes out of sight.
"""
show_menu!(window, items::Vector{String}, x, y, w; item_height=32px, onselect=nothing, theme=theme(), dividers=false, lift=1.0,
           under=nothing, gap=0px, families=String[]) = begin
  list = MenuList(items=items, onselect=onselect, item_height=item_height, dividers=dividers, lift=lift, families=families)
  popup!(window, list, anchor=under === nothing ? (x, y) : under, gap=under === nothing ? 0px : gap, width=w, key=:menu, theme=theme,
         onclose=() -> onselect === nothing || onselect(0))
end

"Hide the floating menu"
hide_menu!(window) = close_popup!(window, :menu)

# --- tooltips ----------------------------------------------------------------

"The dark box of a tooltip, with an arrow that points at what the tooltip is about"
@def mutable struct Bubble <: SemanticUI
  content::Any = nothing
  placement::Symbol = :bottom
  target::NTuple{4,px} = (0px, 0px, 0px, 0px)
end

const bubble_colour = colorant"rgb(50,50,50)"

describe(b::Bubble) = Box(radius(6px), background(bubble_colour), shadow(1px, 1px, 0px, RGBA(0, 0, 0, 0.15)), b.content)

draw(ctx, size, ui::ConcreteRect, b::Bubble) = begin
  (;left, top, width, height) = ui
  x, y, w, h = b.target
  arrow = 5px
  # The arrow points at the middle of the target, even when the tooltip has moved in from the edge of the window
  cx = clamp(x + w/2, left + 6px + arrow, max(left + 6px + arrow, left + width - 6px - arrow))
  cy = top + height/2
  path(ctx, close=true, background=bubble_colour) do p
    if b.placement == :bottom
      move_to(p, (cx - arrow, top)); line_to(p, (cx, top - arrow)); line_to(p, (cx + arrow, top))
    elseif b.placement == :top
      move_to(p, (cx - arrow, top + height)); line_to(p, (cx, top + height + arrow)); line_to(p, (cx + arrow, top + height))
    elseif b.placement == :right
      move_to(p, (left, cy - arrow)); line_to(p, (left - arrow, cy)); line_to(p, (left, cy + arrow))
    else
      move_to(p, (left + width, cy - arrow)); line_to(p, (left + width + arrow, cy)); line_to(p, (left + width, cy + arrow))
    end
  end
end

"""
Show a tooltip beside the rectangle at `(x, y)` that's `w` wide and `h` tall.
`content` is the layout to show in it. `placement` is the side of the
rectangle it goes on: `:bottom`, `:top`, `:left` or `:right`. The mouse goes
through a tooltip, and the next mouse move takes it away.
"""
show_tooltip!(window, content, x, y, w, h; placement=:bottom, gap=4px) =
  popup!(window, Bubble(content=content, placement=placement, target=box((x, y, w, h))), anchor=(x, y, w, h),
         placement=placement, gap=gap, key=:tooltip, input=false)

hide_tooltip!(window) = close_popup!(window, :tooltip)

Base.setproperty!(w::AbstractWindow, ::Field{:ui}, node::UITree) = begin
  Root(node, window=w)
  setfield!(w, :ui, node)
end

Window(child::UITree; kwargs...) = begin
  w = Window(; kwargs...)
  w.ui = child
  w
end

ui(window) = window.ui

const _scenes = Dict{UInt, ConcreteRect}()

"The layout a window last drew: the rectangle of its whole app, with a rectangle in it for each element. `nothing` before the first frame."
scene(w::AbstractWindow) = get(_scenes, objectid(w), nothing)

# Each window's list of where its last layout put each semantic node. It's made
# the first time `rect` is asked for one after a frame.
const _rects = Dict{UInt, IdDict{SemanticUI,ConcreteRect}}()

index_rects!(index, ui::ConcreteRect) = begin
  from = ui.from
  source = from isa GeometricUI ? from.from : nothing
  source isa SemanticUI && get!(index, source, ui)
  for child in ui.children
    child isa ConcreteRect && index_rects!(index, child)
  end
  index
end

"""
Where the last layout put `node`: the rectangle that its `describe` came out
as, with `left`, `top`, `width` and `height`, and the rectangles of its
geometry in `children`. It's `nothing` when `node` isn't in a window, or wasn't
in the last frame. Use it in an event handler to learn where a click landed in
the node, or where to put a menu:

    onkey(d::Dropdown, e::KeyPress{Keys.mouse_left}) = (r = rect(d); show_menu!(e.window, d.options, r.left, r.top + r.height, r.width))
"""
rect(node::SemanticUI) = begin
  w = window_of(node)
  w === nothing && return nothing
  index = get!(_rects, objectid(w)) do
    index = IdDict{SemanticUI,ConcreteRect}()
    s = scene(w)
    s === nothing || index_rects!(index, s)
    for popup in popups(w)
      popup.scene === nothing || index_rects!(index, popup.scene)
    end
    index
  end
  found = get(index, node, nothing)
  (found !== nothing || getfield(node, :slot) == 0) && return found
  # `node` was made by a `describe` on an earlier frame. This frame's one is where it is now.
  for (other, r) in index
    same(other, node) && return r
  end
  nothing
end

# Each window keeps the layout it resolved last: the geometric tree it came from,
# the size, how many changes had been made to layouts by then, and the result.
# `frame` uses it again when the app returns the same geometric tree, the window
# is the same size and no layout has been changed since. Then only `position!`
# runs, to move what a Scroll has scrolled. An app whose `describe` makes a new
# geometric tree on each frame never has a layout to use again.
const _layout_cache = Dict{UInt, Tuple{UInt, Vec2{px}, Int, ConcreteRect}}()

"""
Forget the layout that was kept for a window. A window notices a change to a
layout by itself, so this is only for a change it can't see, like a font
registered under a name that's already in use.
"""
invalidate_layout!(w::AbstractWindow) = (delete!(_layout_cache, objectid(w)); epoch[] += 1; nothing)

resolve_layout(geo::Container, size, window_id::UInt) = begin
  cached = get(_layout_cache, window_id, nothing)
  if cached !== nothing && cached[1] == objectid(geo) && cached[2] == size && cached[3] == edits[]
    cui = cached[4]
    position!(geo, cui)
    return cui
  end
  cui = describe(geo, size)
  _layout_cache[window_id] = (objectid(geo), size, edits[], cui)
  cui
end

# Tools like the layout inspector that share the window with the app. Each
# window can have one. The tool decides how much room the app gets, draws
# itself after the app, and sees input before the app does.
const _tools = Dict{UInt, Any}()

"How much of the window `tool` leaves for the app"
app_size(tool, size) = size
"Draw `tool` over the app's `scene`"
draw_tool(ctx, window, tool, scene) = nothing
"Give `tool` first look at an input event. Return true if it used the event."
tool_input(tool, window, event) = false

"""
The size the app in `node`'s window is laid out at, or `nothing` when `node`
isn't shown in a window. Use it in `describe` to switch layouts by width.
"""
viewport(node::UITree) = begin
  w = window_of(node)
  w === nothing && return nothing
  app_size(get(_tools, objectid(w), nothing), w.size)
end

set_tool!(w::AbstractWindow, tool) = (_tools[objectid(w)] = tool; invalidate_layout!(w))
clear_tool!(w::AbstractWindow) = (delete!(_tools, objectid(w)); invalidate_layout!(w))
window_tool(w::AbstractWindow) = get(_tools, objectid(w), nothing)

# A window draws only when something happens to it. A node that changes with
# time, like one that animates, asks for the next frame on each frame until it
# stops changing. The window then wakes that soon, and when the node stops
# asking, it goes back to the wake it had.
const _soon = Dict{UInt, Float64}()
const _hurried = Dict{UInt, Tuple{Float64,Float64}}()   # the wake the window had, and the wake it was given

"Ask the window that shows `node` to draw again within `seconds`"
redraw_in!(node::UITree, seconds) = begin
  # A `describe` that asks for another frame changes with time, so it can't be skipped on that frame
  timed!()
  w = window_of(node)
  w === nothing && return
  id = objectid(w)
  _soon[id] = min(get(_soon, id, Inf), Float64(seconds))
  nothing
end

"Make the window wake as soon as a node asked it to in this frame, or give it back its own wake"
hurry!(w::AbstractWindow) = begin
  id = objectid(w)
  soon = pop!(_soon, id, nothing)
  last = get(_hurried, id, nothing)
  if soon !== nothing
    # The app may set the wake on each frame. If it didn't, the wake is still the one given last frame.
    had = last !== nothing && w.wake == last[2] ? last[1] : w.wake
    w.wake = had > 0 ? min(had, soon) : max(soon, 0.001)
    _hurried[id] = (had, w.wake)
  elseif last !== nothing
    delete!(_hurried, id)
    w.wake == last[2] && (w.wake = last[1])
  end
end

"How long each stage of a window's last frame took, in milliseconds"
@def mutable struct FrameStats
  describe::Float64 = 0.0
  layout::Float64 = 0.0
  draw::Float64 = 0.0
  elements::Int = 0
end

const _stats = Dict{UInt, FrameStats}()

"Timings for the most recent frame drawn in `w`"
frame_stats(w::AbstractWindow) = get!(FrameStats, _stats, objectid(w))

count_elements(ui::ConcreteRect) = begin
  # A loop rather than `sum`, so a trimmed app only needs the count_elements methods
  n = 1
  for child in ui.children
    n += count_elements(child)
  end
  n
end
count_elements(::ConcreteUI) = 1

frame(window::Window) = begin
  id = objectid(window)
  stats = frame_stats(window)
  t = get(_tools, id, nothing)
  t0 = time_ns()
  geo = convert(GeometricUI, ui(window))
  t1 = time_ns()
  scene = resolve_layout(geo, app_size(t, window.size), id)
  t2 = time_ns()
  _scenes[id] = scene
  delete!(_rects, id)
  follow!(window, scene)
  shown = popups(window)
  for popup in shown
    place!(popup, scene.size)
  end
  update_hover!(window, scene)
  pixels = drawing(window, scene) do ctx, size, scene
    draw(ctx, size, scene)
    for popup in shown
      draw(ctx, popup.scene.size, popup.scene)
    end
    t === nothing || draw_tool(ctx, window, t, scene)
  end
  stats.describe = (t1 - t0) / 1e6
  stats.layout = (t2 - t1) / 1e6
  stats.draw = (time_ns() - t2) / 1e6
  stats.elements = count_elements(scene)
  hurry!(window)
  pixels
end

Base.display(w::Window) = open(w)

"""
MiniFB calls `onopen(window)` once the window is open. UI.jl passes it on to
`onopen(ui, window)`, so each app can do what its window needs then, like
`hide_titlebar!`, without replacing what another app loaded alongside it does.
"""
onopen(w::Window) = onopen(w.ui, w)
onopen(ui, w::Window) = nothing

"""
MiniFB calls `onfiledrop(window, paths)` when files from the Finder are dropped
on the window. UI.jl passes it on to `onfiledrop(ui, window, paths)`, so an app
can take the files. `window.mouse` is where they were dropped.
"""
onfiledrop(w::Window, paths) = (sync_mouse!(w); onfiledrop(w.ui, w, paths))
onfiledrop(ui, w::Window, paths) = nothing

"Walk the from chain to find the SemanticUI that produced this concrete node"
semantic_source(ui::Union{ConcreteRect,ConcreteText}) = begin
  from = ui.from
  while from !== nothing
    from isa SemanticUI && return from
    from = hasproperty(from, :from) ? from.from : nothing
  end
  nothing
end

inside(ui::ConcreteUI, (x, y)) =
  ui.left <= x <= ui.left + ui.width && ui.top <= y <= ui.top + ui.height && on_shape(ui.from, ui, (x, y))

"Find the deepest SemanticUI node under the given position"
hittest(ui::ConcreteRect, pos) = begin
  inside(ui, pos) || return nothing
  # Later children draw on top, so they get first claim on the cursor
  for child in Iterators.reverse(ui.children)
    result = hittest(child, pos)
    result !== nothing && return result
  end
  semantic_source(ui)
end
hittest(::ConcreteText, pos) = nothing

"""
Find the SemanticUI node under the mouse cursor, or under `pos`. Inside a
`MouseMove` handler, pass the event's position: the window records where the
mouse is only after the handler returns.
"""
hittest(w::Window, pos=w.mouse) = begin
  scene = get(_scenes, objectid(w), nothing)
  scene === nothing && return nothing
  hittest(w, scene, pos)
end

"The semantic node at `pos` in a window whose app is laid out as `scene`. A popup is on top of the app."
hittest(w::Window, scene::ConcreteRect, pos) = begin
  popup = popup_at(w, pos)
  popup === nothing ? hittest(scene, pos) : hittest(popup.scene, pos)
end

"""
The scroll wheel turned, or two fingers moved on the trackpad, while the mouse
was over a node. `delta` is how far, across then up. A node that wants it
defines `onscroll(node, e::MouseScroll)` and returns `handled`. If no node
does, the Scroll under the mouse scrolls.
"""
struct MouseScroll
  delta::Vec2{px}
  window::AbstractWindow
end

"""
Give an event to `target`, then to each semantic node above it in turn. A
handler that returns `handled` keeps the event from the nodes above, and `emit`
then returns `handled` too.
"""
emit(target::SemanticUI, event) = begin
  node = target
  while node !== nothing
    on(node, event) === handled && return handled
    node = semantic_parent(node)
  end
  nothing
end

on(target::SemanticUI, e::KeyEvent) = onkey(target, e)
on(target::SemanticUI, e::MouseMove) = onmouse(target, e)
on(target::SemanticUI, e::Typed) = ontype(target, e)
on(target::SemanticUI, e::MouseScroll) = onscroll(target, e)

"A typed character goes to the node that has the keyboard, then up through the nodes above it"
ontype(w::Window, e::Typed) = begin
  t = get(_tools, objectid(w), nothing)
  t !== nothing && tool_input(t, w, e) && return
  w.focus === nothing || emit(w.focus, e)
end

# What each key types on a US keyboard, alone and with Shift
const us_keys = Dict{Keys,Tuple{Char,Char}}()
for c in 'a':'z'; us_keys[getproperty(Keys, Symbol(c))] = (c, uppercase(c)) end
for (d, shifted) in zip(0:9, ")!@#\$%^&*(")
  us_keys[getproperty(Keys, Symbol(d))] = (Char('0' + d), shifted)
  us_keys[getproperty(Keys, Symbol(:num, d))] = (Char('0' + d), Char('0' + d))
end
for (key, chars) in (:space => "  ", :tilde => "`~", :minus => "-_", :equal => "=+", :left_bracket => "[{", :right_bracket => "]}",
                     :semicolon => ";:", :apostrophe => "'\"", :comma => ",<", :period => ".>", :slash => "/?", :backslash => "\\|",
                     :plus => "++", :times => "**")
  us_keys[getproperty(Keys, key)] = (chars[1], chars[2])
end

"What a key press types on a US keyboard, or `nothing` if it types nothing"
us_char(::Any, w) = nothing
us_char(::KeyPress{K}, w) where K = begin
  (Keys.cmd in w.keys || Keys.ctrl in w.keys) && return nothing
  chars = get(us_keys, K, nothing)
  chars === nothing ? nothing : chars[Keys.shft in w.keys ? 2 : 1]
end

# A window that isn't open has no clipboard to ask, so this stands in for it. Tests use it.
const pasteboard = Ref("")

"The text on the system's clipboard"
clipboard(w::AbstractWindow) = begin
  isempty(w.glfw) && return pasteboard[]
  text = ccall((:glfwGetClipboardString, GLFW.libglfw), Cstring, (GLFW.Window,), w.glfw[1])
  text == C_NULL ? "" : unsafe_string(text)
end

"Put `text` on the system's clipboard"
clipboard!(w::AbstractWindow, text::AbstractString) = begin
  if isempty(w.glfw)
    pasteboard[] = String(text)
  else
    ccall((:glfwSetClipboardString, GLFW.libglfw), Cvoid, (GLFW.Window, Cstring), w.glfw[1], String(text))
  end
  nothing
end

# Hover tracking. After each layout and each mouse move the window records
# which semantic nodes sit under the cursor: the deepest one and all of its
# semantic ancestors. `describe` methods ask `ishovered(self)` to pick a hover
# style, the same way Clay's `Clay_Hovered()` works.
const _hovered = Dict{UInt, Vector{SemanticUI}}()

hover_chain(target) = begin
  chain = SemanticUI[]
  node = target
  while node !== nothing && !(node isa Root)
    push!(chain, node)
    node = semantic_parent(node)
  end
  chain
end

# What a window adds to the inputs of a node that says what its `describe` reads: whether the mouse
# is over it, whether it has the keyboard, and the size the app is laid out at
ambient(node::SemanticUI) = begin
  w = window_of(node)
  w === nothing && return UInt(0)
  id = objectid(w)
  hovered = any(n -> same(n, node), get(_hovered, id, ()))
  hash((hovered, w.focus === node, app_size(get(_tools, id, nothing), w.size)))
end

"True when the cursor is over `node` or one of its descendants"
ishovered(node::SemanticUI) = begin
  w = window_of(node)
  w === nothing && return false
  any(n -> same(n, node), get(_hovered, objectid(w), ()))
end

"""
The mouse cursor to show over a node: `:hand`, `:ibeam`, `:crosshair`,
`:resize_x` (arrows that point left and right, for an edge that you drag) or
`nothing` to leave it to the node's parent.
"""
cursor(::SemanticUI) = nothing

const cursor_shapes = Dict(:arrow => GLFW.ARROW_CURSOR, :hand => GLFW.HAND_CURSOR,
                           :ibeam => GLFW.IBEAM_CURSOR, :crosshair => GLFW.CROSSHAIR_CURSOR,
                           :resize_x => GLFW.HRESIZE_CURSOR)
const _cursor_shape = Dict{UInt, Symbol}()

set_cursor!(w::Window, shape::Symbol) = begin
  get(_cursor_shape, objectid(w), :arrow) == shape && return
  _cursor_shape[objectid(w)] = shape
  isempty(w.glfw) || (w.cursor = cursor_shapes[shape])
end

update_hover!(w::Window, scene::ConcreteRect, pos=w.mouse) = begin
  id = objectid(w)
  chain = hover_chain(hittest(w, scene, pos))
  old = get(_hovered, id, SemanticUI[])
  # A node can change its cursor while the mouse stays over it, e.g. when a key goes down.
  # An open menu is over the rest of the window: a hand over its items, and an arrow everywhere else.
  behind_popup = key_popup(w) !== nothing && popup_at(w, pos) === nothing
  set_cursor!(w, behind_popup ? :arrow : something((cursor(n) for n in chain)..., :arrow))
  _hovered[id] = chain
  # A node that `describe` makes afresh on each frame is still the node it was
  length(chain) == length(old) && (isempty(chain) || same(chain[1], old[1])) && return false
  # The hover style changes the next frame, so make sure there is one
  isempty(w.glfw) || GLFW.PostEmptyEvent()
  true
end

"Open a URL or file with the system's default application"
open_url(url::AbstractString) = begin
  cmd = Sys.isapple() ? `open $url` : Sys.iswindows() ? `cmd /c start "" $url` : `xdg-open $url`
  run(pipeline(cmd, stdout=devnull, stderr=devnull), wait=false)
  nothing
end

const _captured = Dict{UInt, SemanticUI}()

is_mouse_button(::KeyPress{K}) where K =
  K == Keys.mouse_left || K == Keys.mouse_right || K == Keys.mouse_middle
is_mouse_button(_) = false

# Scrollbar dragging, per window: the Scroll being dragged, the track it
# moves along, and how far below the thumb's top edge it was grabbed.
const _scroll_drag = Dict{UInt, NamedTuple}()

"The Scroll whose scrollbar thumb is under `pos`, along with its geometry"
thumb_at(rect::ConcreteRect, pos) = begin
  inside(rect, pos) || return nothing
  for child in rect.children
    child isa ConcreteRect || continue
    found = thumb_at(child, pos)
    found === nothing || return found
  end
  rect.from isa Scroll || return nothing
  scrollbar_visible(rect.from) || return nothing
  g = scrollbar_geometry(rect, rect.from)
  g === nothing && return nothing
  (g.x - 4px <= pos[1] <= g.x + g.width + 4px && g.thumb_y <= pos[2] <= g.thumb_y + g.thumb_h) || return nothing
  (scroll=rect.from, geometry=g)
end

start_scroll_drag!(w::Window, scene, pos) = begin
  found = thumb_at(scene, pos)
  found === nothing && return false
  (;scroll, geometry) = found
  scroll.dragging = true
  _scroll_drag[objectid(w)] = (scroll=scroll, geometry=geometry, grab=pos[2] - geometry.thumb_y)
  true
end

drag_scroll!(w::Window, pos) = begin
  drag = get(_scroll_drag, objectid(w), nothing)
  drag === nothing && return false
  g = drag.geometry
  travel = max(1px, g.height - g.thumb_h)
  ratio = clamp((pos[2] - drag.grab - g.y) / travel, 0.0, 1.0)
  drag.scroll.offset = ratio * g.range
  true
end

end_scroll_drag!(w::Window) = begin
  drag = pop!(_scroll_drag, objectid(w), nothing)
  drag === nothing && return false
  drag.scroll.dragging = false
  true
end

"""
Read where the cursor is from GLFW. A click can arrive with no move before it,
like the click that brings an inactive window to the front, so the last move
event may be out of date.
"""
sync_mouse!(w::Window) = begin
  isempty(w.glfw) && return
  x, y = GLFW.GetCursorPos(w.glfw[1])
  pos = Vec2{px}(px(x), px(y))
  pos == w.mouse && return
  w.mouse = pos
  scene = get(_scenes, objectid(w), nothing)
  scene === nothing || update_hover!(w, scene, pos)
end

onkey(w::Window, e) = begin
  route_key(w, e)
  # An open window is told what each key types. One that isn't open, as in a test, has no keyboard
  # to ask, so its keys type what they would on a US keyboard.
  if isempty(w.glfw)
    char = us_char(e, w)
    char === nothing || ontype(w, Typed(char, w))
  end
  nothing
end

"Give a key or mouse button event to the part of the window it's for"
route_key(w::Window, e) = begin
  id = objectid(w)
  is_mouse_button(e) && sync_mouse!(w)
  t = get(_tools, id, nothing)
  t !== nothing && tool_input(t, w, e) && return
  if is_mouse_button(e)
    popup = popup_at(w, w.mouse)
    if popup !== nothing
      # A click in a popup goes to the node under it, and never to the app behind
      target = hittest(popup.scene, w.mouse)
      target === nothing || (_captured[id] = target; emit(target, e))
      return
    elseif key_popup(w) !== nothing
      # A click outside closes every popup that takes input, and the app doesn't see it
      foreach(p -> dismiss!(w, p), filter(p -> p.input, collect(popups(w))))
      return
    end
  elseif e isa KeyPress
    # A popup sees a key before the node that has the keyboard, and Escape closes it
    popup = key_popup(w)
    if popup !== nothing
      popup.content isa SemanticUI && emit(popup.content, e) === handled && return
      e isa KeyPress{Keys.escape} && return dismiss!(w, popup)
    end
  end
  scene = get(_scenes, id, nothing)
  e isa KeyRelease{Keys.mouse_left} && end_scroll_drag!(w) && return
  if e isa KeyPress{Keys.mouse_left} && scene !== nothing && start_scroll_drag!(w, scene, w.mouse)
    return
  end
  if is_mouse_button(e)
    target = hittest(w)
    if target !== nothing
      _captured[id] = target
      emit(target, e)
    end
  elseif w.focus !== nothing
    emit(w.focus, e)
  elseif e isa KeyPress && scene !== nothing
    scroll_by_key!(w, scene, e)
  end
end

"Walk a concrete tree and return the deepest ConcreteRect whose
geometric source is a Scroll and that contains `pos`. Returns nothing
if the cursor isn't inside any scroll viewport. Bails on each
out-of-bounds rect immediately, so cost is O(depth + matching siblings)
not O(tree size)."
find_scroll_at(::Any, _) = nothing
find_scroll_at(rect::ConcreteRect, pos) = begin
  inside(rect, pos) || return nothing
  for child in rect.children
    found = find_scroll_at(child, pos)
    found === nothing || return found
  end
  rect.from isa Scroll ? rect : nothing
end

"The first Scroll in a concrete tree, searching breadth first"
first_scroll(rect::ConcreteRect) = begin
  queue = ConcreteUI[rect]
  while !isempty(queue)
    node = popfirst!(queue)
    node isa ConcreteRect || continue
    node.from isa Scroll && return node
    append!(queue, node.children)
  end
  nothing
end

scroll_step(rect, ::KeyPress{Keys.down}) = 50px
scroll_step(rect, ::KeyPress{Keys.up}) = -50px
scroll_step(rect, ::KeyPress{Keys.pagedown}) = rect.height - 40px
scroll_step(rect, ::KeyPress{Keys.pageup}) = 40px - rect.height
scroll_step(rect, ::KeyPress{Keys.space}) = rect.height - 40px
scroll_step(rect, ::KeyPress{Keys.home}) = px(-Inf)
scroll_step(rect, ::KeyPress{Keys._end}) = px(Inf)
scroll_step(rect, _) = nothing

"When nothing has keyboard focus, arrow and page keys scroll the Scroll under
the cursor, or the first one in the window."
scroll_by_key!(w::Window, scene, e) = begin
  rect = something(find_scroll_at(scene, w.mouse), first_scroll(scene), Some(nothing))
  rect === nothing && return
  step = scroll_step(rect, e)
  step === nothing && return
  scroll = rect.from::Scroll
  scroll.offset = clamp(scroll.offset + step, 0px, max(0px, scroll.content_height - rect.height))
end

# Per-window memo of which Scroll is currently hovered. Lets the
# mouse-move handler bail on the common case (cursor stays inside the
# same scroll, or stays outside all scrolls) without ever touching the
# tree past the find_scroll_at walk.
const _hovered_scroll = Dict{UInt, Scroll}()

update_scroll_hover!(w, scene::ConcreteRect, pos) = begin
  id = objectid(w)
  rect = find_scroll_at(scene, pos)
  current = rect === nothing ? nothing : rect.from::Scroll
  prev = get(_hovered_scroll, id, nothing)
  if prev !== nothing && (current === nothing || getfield(prev, :state) !== getfield(current, :state))
    prev.hover = false
    prev.thumb_hover = false
  end
  if current === nothing
    delete!(_hovered_scroll, id)
  else
    current.hover = true
    g = scrollbar_geometry(rect, current)
    current.thumb_hover = g !== nothing && g.x - 4px <= pos[1] && g.thumb_y <= pos[2] <= g.thumb_y + g.thumb_h
    _hovered_scroll[id] = current
  end
end

onscroll(w::Window, delta::Vec2{px}) = begin
  id = objectid(w)
  t = get(_tools, id, nothing)
  t !== nothing && tool_input(t, w, delta) && return
  # The wheel is for the popup under the mouse, or for the app when there's none
  popup = popup_at(w, w.mouse)
  scene = popup === nothing ? get(_scenes, id, nothing) : popup.scene
  target = popup === nothing ? hittest(w) : hittest(scene, w.mouse)
  target !== nothing && emit(target, MouseScroll(delta, w)) === handled && return
  scene === nothing && return
  rects = scrolls_at(scene, w.mouse)
  step = -delta[2] * 30
  (isempty(rects) || step == 0px) && return
  room(rect) = max(0px, rect.from.content_height - rect.height)
  moves(rect) = step < 0px ? rect.from.offset > 0px : rect.from.offset < room(rect)
  # A run of the wheel stays with the Scroll it began in. A new run moves the
  # innermost Scroll that has somewhere to go, so a Scroll at its end lets the
  # one round it move.
  last = get(_wheel, id, nothing)
  i = last !== nothing && time() - last[2] < WHEEL_RUN ? findfirst(r -> getfield(r.from, :state) === last[1], rects) : nothing
  i === nothing && (i = something(findfirst(moves, rects), 1))
  rect = rects[i]
  scroll = rect.from::Scroll
  scroll.offset = clamp(scroll.offset + step, 0px, room(rect))
  _wheel[id] = (getfield(scroll, :state), time())
  nothing
end

# What the wheel last scrolled in each window, and when. A page that's moving
# doesn't stop when a smaller Scroll comes under the mouse.
const _wheel = Dict{UInt,Tuple{Any,Float64}}()
const WHEEL_RUN = 0.2   # seconds. Wheel events closer together than this are one run.

"Each Scroll under `pos`, the innermost first"
scrolls_at(::Any, pos, out=ConcreteRect[]) = out
scrolls_at(rect::ConcreteRect, pos, out=ConcreteRect[]) = begin
  inside(rect, pos) || return out
  foreach(child -> scrolls_at(child, pos, out), rect.children)
  rect.from isa Scroll && push!(out, rect)
  out
end

onmouse(w::Window, e::MouseMove) = begin
  id = objectid(w)
  t = get(_tools, id, nothing)
  t !== nothing && tool_input(t, w, e) && return
  drag_scroll!(w, e.position) && return
  scene = get(_scenes, id, nothing)
  if scene !== nothing
    update_scroll_hover!(w, scene, e.position)
    update_hover!(w, scene, e.position)
  end
  # Hide tooltip before emit — if still hovered, Tooltip's onmouse will re-show it
  hide_tooltip!(w)
  popup = popup_at(w, e.position)
  if popup !== nothing
    target = hittest(popup.scene, e.position)
    target === nothing || emit(target, e)
    return
  end
  # While a menu is open the app behind it doesn't follow the mouse
  key_popup(w) === nothing || return
  captured = get(_captured, id, nothing)
  if captured !== nothing
    if Keys.mouse_left in w.keys || Keys.mouse_right in w.keys || Keys.mouse_middle in w.keys
      emit(captured, e)
      return
    end
    delete!(_captured, id)
  end
  target = hittest(w, e.position)
  if target !== nothing
    emit(target, e)
  elseif w.focus !== nothing
    emit(w.focus, e)
  end
end

export draw, ui, hittest, emit, handled, rect, scene, clipboard, clipboard!, popup!, close_popup!, show_menu!, hide_menu!, show_tooltip!, hide_tooltip!, ishovered, cursor, open_url,
       invalidate_layout!, set_tool!, clear_tool!, window_tool, app_size, draw_tool, tool_input, inside, offset!,
       frame_stats, FrameStats, semantic_source, viewport, redraw_in!, MouseScroll
