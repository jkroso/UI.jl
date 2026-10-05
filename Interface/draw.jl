@use "github.com/jkroso/Prospects.jl" Field @def
@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont font_metrics text_bounds
@use "github.com/jkroso/MiniFB.jl"... int KeyEvent flt onscroll
@use "github.com/jkroso/Font.jl" cap_height ["units" px absolute]
@use GeometryBasics: Vec2
@use Colors: @colorant_str, RGBA, Colorant, alpha, red, green, blue
@use Skia
@use GLFW
@use "./abstract" describe Root UITree SemanticUI ConcreteUI window_of
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
      line(ctx, Vec2{px}(x, ui.top), Vec2{px}(x, ui.top + ui.height), border.width, border.color)
    else
      y = (prev.top + prev.height + child.top) / 2
      line(ctx, Vec2{px}(ui.left, y), Vec2{px}(ui.left + ui.width, y), border.width, border.color)
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

"True iff drawing `ui` is a no-op given the canvas's current clip. Lets us
skip the entire subtree of an off-screen child without any rasterization
work. Outside a clip context this always returns false."
@inline function quick_reject(ctx, ui::ConcreteUI)
  rect = Ref(Skia.sk_rect_t(flt(ui.left), flt(ui.top),
                             flt(ui.left + ui.width), flt(ui.top + ui.height)))
  Skia.sk_canvas_quick_reject_rect(ctx, rect)
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
  track_x = ui.left + ui.width - w - margin
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
radius. Otherwise each side is drawn as its own straight edge.
"""
function draw_border(ctx, ui::ConcreteRect)
  (;border, radius) = ui.from
  sides = (border.top, border.right, border.bottom, border.left)
  all(isempty, sides) && return
  if all(==(border.top), sides)
    bw = border.top.width
    rounded_rectangle(ctx, ui.origin .+ bw/2, ui.size .- bw, max(0px, radius.tl - bw/2),
                      color=border.top.color, stroke_width=bw)
  else
    (;left, top, width, height) = ui
    edge(x, y, w, h, side) = isempty(side) || rounded_rectangle(ctx, x, y, w, h, 0px, background=side.color)
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
  r = img.radius.tl
  if r > 0px
    p = Skia.sk_path_new()
    Skia.sk_path_add_rounded_rect(p, dst, flt(r), flt(r), Skia.SK_PATH_DIRECTION_CW)
    Skia.sk_canvas_clip_path_with_operation(ctx, p, Skia.SK_CLIP_OP_INTERSECT, true)
    Skia.sk_path_delete(p)
  end
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_canvas_draw_image_rect(ctx, src.raw, srcrect, dst, opts, paint, Skia.SRC_RECT_CONSTRAINT_FAST)
  Skia.sk_paint_delete(paint)
  Skia.sk_canvas_restore(ctx)
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
  alpha(background.color) > 0 && rounded_rectangle(ctx, ui.origin, ui.size, radius.tl, background=background.color)
  from isa Image && draw_image(ctx, ui, from)
  if from isa Scroll
    with_clip(() -> draw_children(ctx, ui), ctx, ui.left, ui.top, ui.width, ui.height)
  elseif from.clip
    with_clip(ctx, ui.left, ui.top, ui.width, ui.height) do
      draw_children(ctx, ui)
      draw_between(ctx, ui)
    end
  else
    draw_children(ctx, ui)
    draw_between(ctx, ui)
  end
  draw_border(ctx, ui)
  from isa Scroll && draw_scrollbar(ctx, ui, from)
  from.from !== nothing && draw(ctx, size, ui, from.from)
end

draw(ctx, size, ui::ConcreteRect, source) = nothing

draw(ctx, _, ui::ConcreteText) = begin
  f = skia_font(ui.from.family, ui.from.size, ui.from.subfamily)
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

# Overlay system for floating menus
@def mutable struct MenuOverlay
  source::Any = nothing
  items::Vector{String} = String[]
  hover::Int = 0
  x::px = 0px
  y::px = 0px
  width::px = 150px
  item_height::px = 32px
  onselect::Any = nothing
end

const _overlay = Dict{UInt, MenuOverlay}()

"Show a floating menu overlay on a window"
show_menu!(window, items::Vector{String}, x, y, w; item_height=32px, onselect=nothing, source=nothing) = begin
  _overlay[objectid(window)] = MenuOverlay(source=source, items=items, x=x, y=y, width=w, item_height=item_height, onselect=onselect)
end

"Hide the floating menu overlay"
hide_menu!(window) = delete!(_overlay, objectid(window))

"Returns 1-based item index if pos is inside the menu, or 0 if outside"
menu_hittest(ov::MenuOverlay, (x, y)) = begin
  if ov.source !== nothing
    n = length(ov.source.children)
    pad_y = 5px
  else
    n = length(ov.items)
    pad_y = 0px
  end
  x < ov.x && return 0
  x > ov.x + ov.width && return 0
  y < ov.y + pad_y && return 0
  total_height = ov.item_height * n
  y > ov.y + pad_y + total_height && return 0
  clamp(Int(floor(int(y - ov.y - pad_y) / int(ov.item_height))) + 1, 1, n)
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

"Draw a Menu component overlay"
draw_menu_source(ctx, ov) = begin
  # Update hover states on Items
  for (i, item) in enumerate(ov.source.children)
    item.hover = (i == ov.hover)
  end
  # Describe and resolve
  geo = describe(ov.source)
  geo.from = ov.source
  concrete = describe(geo, (ov.width, 9999px))
  offset!(concrete, ov.x, ov.y)
  # Shadow
  rounded_rectangle(ctx, ov.x + 2px, ov.y + 2px, concrete.width, concrete.height, 6px,
                    background=RGBA(0,0,0,0.15))
  # Draw the resolved component tree
  draw(ctx, concrete.size, concrete)
end

"Draw the menu overlay"
draw_menu(ctx, ov::MenuOverlay) = begin
  if ov.source !== nothing
    return draw_menu_source(ctx, ov)
  end
  n = length(ov.items)
  n == 0 && return
  total_h = ov.item_height * n
  # shadow
  rounded_rectangle(ctx, ov.x + 2px, ov.y + 2px, ov.width, total_h, 6px,
                    background=RGBA(0,0,0,0.15))
  # background
  rounded_rectangle(ctx, ov.x, ov.y, ov.width, total_h, 6px,
                    background=colorant"white",
                    color=colorant"rgb(200,200,200)", stroke_width=1px)
  f = skia_font("Helvetica", 13pt)
  for (i, item) in enumerate(ov.items)
    iy = ov.y + (i - 1) * ov.item_height
    if i == ov.hover
      # clip hover highlight to rounded rect bounds
      if n == 1
        rounded_rectangle(ctx, ov.x + 1px, iy + 1px, ov.width - 2px, ov.item_height - 2px, 5px,
                          background=colorant"rgb(235,238,245)")
      elseif i == 1
        rounded_rectangle(ctx, ov.x + 1px, iy + 1px, ov.width - 2px, ov.item_height - 1px, 5px,
                          background=colorant"rgb(235,238,245)")
      elseif i == n
        rounded_rectangle(ctx, ov.x + 1px, iy, ov.width - 2px, ov.item_height - 1px, 5px,
                          background=colorant"rgb(235,238,245)")
      else
        rounded_rectangle(ctx, ov.x + 1px, iy, ov.width - 2px, ov.item_height, 0px,
                          background=colorant"rgb(235,238,245)")
      end
    end
    text_y = iy + ov.item_height / 2 + 5px
    text(ctx, (ov.x + 12px, text_y), f, colorant"rgb(30,30,30)", item)
  end
end

# Tooltip overlay system
@def mutable struct TooltipOverlay
  content::Any = nothing
  x::px = 0px
  y::px = 0px
  target_w::px = 0px
  target_h::px = 0px
  placement::Symbol = :bottom
  gap::px = 4px
end

const _tooltip = Dict{UInt, TooltipOverlay}()

show_tooltip!(window, content, x, y, w, h; placement=:bottom, gap=4px) = begin
  _tooltip[objectid(window)] = TooltipOverlay(content=content, x=x, y=y, target_w=w, target_h=h, placement=placement, gap=gap)
end

hide_tooltip!(window) = delete!(_tooltip, objectid(window))

"Draw the tooltip overlay"
draw_tooltip(ctx, ov::TooltipOverlay) = begin
  ov.content === nothing && return
  # resolve content through normal pipeline
  concrete = describe(ov.content, (9999px, 9999px))
  tw = concrete.width
  th = concrete.height
  # position relative to target
  if ov.placement == :bottom
    tx = ov.x + ov.target_w/2 - tw/2
    ty = ov.y + ov.target_h + ov.gap
  elseif ov.placement == :top
    tx = ov.x + ov.target_w/2 - tw/2
    ty = ov.y - th - ov.gap
  elseif ov.placement == :right
    tx = ov.x + ov.target_w + ov.gap
    ty = ov.y + ov.target_h/2 - th/2
  else # :left
    tx = ov.x - tw - ov.gap
    ty = ov.y + ov.target_h/2 - th/2
  end
  bg = colorant"rgb(50,50,50)"
  arrow_size = 5px
  # shadow
  rounded_rectangle(ctx, tx + 1px, ty + 1px, tw, th, 6px,
                    background=RGBA(0,0,0,0.15))
  # background
  rounded_rectangle(ctx, tx, ty, tw, th, 6px, background=bg)
  # arrow
  cx = tx + tw/2
  cy = ty + th/2
  path(ctx, close=true, background=bg) do p
    if ov.placement == :bottom
      move_to(p, (cx - arrow_size, ty))
      line_to(p, (cx, ty - arrow_size))
      line_to(p, (cx + arrow_size, ty))
    elseif ov.placement == :top
      move_to(p, (cx - arrow_size, ty + th))
      line_to(p, (cx, ty + th + arrow_size))
      line_to(p, (cx + arrow_size, ty + th))
    elseif ov.placement == :right
      move_to(p, (tx, cy - arrow_size))
      line_to(p, (tx - arrow_size, cy))
      line_to(p, (tx, cy + arrow_size))
    else # :left
      move_to(p, (tx + tw, cy - arrow_size))
      line_to(p, (tx + tw + arrow_size, cy))
      line_to(p, (tx + tw, cy + arrow_size))
    end
  end
  # draw resolved content at tooltip position
  offset!(concrete, tx, ty)
  draw(ctx, concrete.size, concrete)
end

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

# Per-window memo of (geometric-tree id, size, ConcreteRect tree).
# `frame` reuses the cached tree whenever the geometric input is the same
# instance and the window hasn't been resized — `initialize` and `fit!`
# produce identical output in that case, so we skip them and just rerun
# `position!` to pick up scroll-offset changes (and any other state that
# only affects coordinates). `describe(::SemanticUI)` that produces a
# fresh geometric tree each frame will always miss the cache and hit the
# full pipeline, which is correct.
const _layout_cache = Dict{UInt, Tuple{UInt, Vec2{px}, ConcreteRect}}()

invalidate_layout!(w::AbstractWindow) = (delete!(_layout_cache, objectid(w)); nothing)

resolve_layout(geo::Container, size, window_id::UInt) = begin
  cached = get(_layout_cache, window_id, nothing)
  if cached !== nothing && cached[1] == objectid(geo) && cached[2] == size
    cui = cached[3]
    position!(geo, cui)
    return cui
  end
  cui = describe(geo, size)
  _layout_cache[window_id] = (objectid(geo), size, cui)
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

count_elements(ui::ConcreteRect) = 1 + sum(count_elements, ui.children, init=0)
count_elements(::ConcreteUI) = 1

frame(window::Window) = begin
  id = objectid(window)
  stats = frame_stats(window)
  t = get(_tools, id, nothing)
  t0 = time_ns()
  geo = describe(ui(window))
  t1 = time_ns()
  scene = resolve_layout(geo, app_size(t, window.size), id)
  t2 = time_ns()
  _scenes[id] = scene
  update_hover!(window, scene)
  ov = get(_overlay, id, nothing)
  tt = get(_tooltip, id, nothing)
  pixels = drawing(window, scene) do ctx, size, scene
    draw(ctx, size, scene)
    ov !== nothing && draw_menu(ctx, ov)
    tt !== nothing && draw_tooltip(ctx, tt)
    t === nothing || draw_tool(ctx, window, t, scene)
  end
  stats.describe = (t1 - t0) / 1e6
  stats.layout = (t2 - t1) / 1e6
  stats.draw = (time_ns() - t2) / 1e6
  stats.elements = count_elements(scene)
  pixels
end

Base.display(w::Window) = open(w)

"Walk the from chain to find the SemanticUI that produced this concrete node"
semantic_source(ui::Union{ConcreteRect,ConcreteText}) = begin
  from = ui.from
  while from !== nothing
    from isa SemanticUI && return from
    from = hasproperty(from, :from) ? from.from : nothing
  end
  nothing
end

inside(ui::ConcreteUI, (x, y)) = ui.left <= x <= ui.left + ui.width && ui.top <= y <= ui.top + ui.height

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

"Find the SemanticUI node under the mouse cursor"
hittest(w::Window) = begin
  scene = get(_scenes, objectid(w), nothing)
  scene === nothing && return nothing
  hittest(scene, w.mouse)
end

"Dispatch an event to a target, bubbling up through parent SemanticUI nodes"
emit(target::SemanticUI, event) = begin
  node = target
  while node !== nothing
    on(node, event)
    node = node.parent
    while node !== nothing && !(node isa SemanticUI)
      node = node.parent
    end
  end
end

on(target::SemanticUI, e::KeyEvent) = onkey(target, e)
on(target::SemanticUI, e::MouseMove) = onmouse(target, e)

# Hover tracking. After each layout and each mouse move the window records
# which semantic nodes sit under the cursor: the deepest one and all of its
# semantic ancestors. `describe` methods ask `ishovered(self)` to pick a hover
# style, the same way Clay's `Clay_Hovered()` works.
const _hovered = Dict{UInt, Vector{SemanticUI}}()

semantic_parent(node) = begin
  node = node.parent
  while node !== nothing && !(node isa SemanticUI)
    node = node.parent
  end
  node
end

hover_chain(target) = begin
  chain = SemanticUI[]
  node = target
  while node !== nothing && !(node isa Root)
    push!(chain, node)
    node = semantic_parent(node)
  end
  chain
end

"True when the cursor is over `node` or one of its descendants"
ishovered(node::SemanticUI) = begin
  w = window_of(node)
  w === nothing && return false
  any(n -> n === node, get(_hovered, objectid(w), ()))
end

"""
The mouse cursor to show over a node: `:hand`, `:ibeam`, `:crosshair` or
`nothing` to leave it to the node's parent.
"""
cursor(::SemanticUI) = nothing

const cursor_shapes = Dict(:arrow => GLFW.ARROW_CURSOR, :hand => GLFW.HAND_CURSOR,
                           :ibeam => GLFW.IBEAM_CURSOR, :crosshair => GLFW.CROSSHAIR_CURSOR)
const _cursor_shape = Dict{UInt, Symbol}()

set_cursor!(w::Window, shape::Symbol) = begin
  get(_cursor_shape, objectid(w), :arrow) == shape && return
  _cursor_shape[objectid(w)] = shape
  isempty(w.glfw) || (w.cursor = cursor_shapes[shape])
end

update_hover!(w::Window, scene::ConcreteRect, pos=w.mouse) = begin
  id = objectid(w)
  chain = hover_chain(hittest(scene, pos))
  old = get(_hovered, id, SemanticUI[])
  length(chain) == length(old) && all(a === b for (a, b) in zip(chain, old)) && return false
  _hovered[id] = chain
  shape = something((cursor(n) for n in chain)..., :arrow)
  set_cursor!(w, shape)
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

onkey(w::Window, e) = begin
  id = objectid(w)
  t = get(_tools, id, nothing)
  t !== nothing && tool_input(t, w, e) && return
  ov = get(_overlay, id, nothing)
  if ov !== nothing && is_mouse_button(e)
    if e isa KeyPress{Keys.mouse_left} && ov.onselect !== nothing
      idx = menu_hittest(ov, w.mouse)
      ov.onselect(idx) # 0 if clicked outside
    end
    hide_menu!(w)
    return
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
  if prev !== nothing && prev !== current
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
  scene = get(_scenes, id, nothing)
  scene === nothing && return
  rect = find_scroll_at(scene, w.mouse)
  rect === nothing && return
  scroll = rect.from::Scroll
  max_offset = max(0px, scroll.content_height - rect.height)
  step = -delta[2] * 30
  scroll.offset = clamp(scroll.offset + step, 0px, max_offset)
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
  ov = get(_overlay, id, nothing)
  if ov !== nothing
    ov.hover = menu_hittest(ov, e.position)
    return
  end
  # Hide tooltip before emit — if still hovered, Tooltip's onmouse will re-show it
  haskey(_tooltip, id) && hide_tooltip!(w)
  captured = get(_captured, id, nothing)
  if captured !== nothing
    if Keys.mouse_left in w.keys || Keys.mouse_right in w.keys || Keys.mouse_middle in w.keys
      emit(captured, e)
      return
    end
    delete!(_captured, id)
  end
  target = hittest(w)
  if target !== nothing
    emit(target, e)
  elseif w.focus !== nothing
    emit(w.focus, e)
  end
end

export draw, ui, hittest, emit, show_menu!, hide_menu!, show_tooltip!, hide_tooltip!, ishovered, cursor, open_url,
       invalidate_layout!, set_tool!, clear_tool!, window_tool, app_size, draw_tool, tool_input, inside, offset!,
       frame_stats, FrameStats, semantic_source, viewport
