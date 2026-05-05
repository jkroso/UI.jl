@use "github.com/jkroso/Prospects.jl" Field @def
@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont font_metrics text_bounds
@use "github.com/jkroso/MiniFB.jl"... int KeyEvent
@use "github.com/jkroso/Font.jl" cap_height ["units" px absolute]
@use GeometryBasics: Vec2
@use Colors: @colorant_str, RGBA, alpha
@use "./abstract" describe Root UITree SemanticUI
@use "./Geometric"...
@use "./Specific"...

draw_between_row(ctx, ui, left) = begin
  border = ui.from.border.between
  border.width > 0 || return
  start = Vec2{px}(left+border.width/2, ui.top)
  finish = Vec2{px}(left+border.width/2, ui.top + ui.height)
  line(ctx, start, finish, border.width, border.color)
end

draw_between_column(ctx, ui, top) = begin
  border = ui.from.border.between
  border.width > 0 || return
  offset = top+border.width/2
  start = Vec2{px}(ui.left, offset)
  finish = Vec2{px}(ui.left + ui.width, offset)
  line(ctx, start, finish, border.width, border.color)
end

draw(ctx, size, ui::ConcreteRect) = begin
  (;background, border, radius) = ui.from
  bw = border.top.width
  tl = ui.origin .+ bw/2
  sz = ui.size .- bw
  bg = alpha(background.color) > 0 ? background.color : nothing
  rounded_rectangle(ctx, tl, sz, radius.tl, background=bg,
                                             color=isempty(border.top) ? nothing : border.top.color,
                                             stroke_width=bw)
  isfirst = true
  if ui.from isa Row
    left = ui.left
    for child in ui.children
      draw(ctx, child.size, child)
      isfirst || draw_between_row(ctx, ui, left)
      isfirst = false
      left += child.width + ui.from.between_width
    end
  else
    top = ui.top
    for child in ui.children
      draw(ctx, child.size, child)
      isfirst || draw_between_column(ctx, ui, top)
      isfirst = false
      top += child.height + ui.from.between_width
    end
  end
  ui.from.from !== nothing && draw(ctx, size, ui, ui.from.from)
end

draw(ctx, size, ui::ConcreteRect, source) = nothing

draw(ctx, _, ui::ConcreteText) = begin
  f = SkiaFont(ui.from.family, ui.from.size)
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
  f = SkiaFont("Helvetica", 13pt)
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

frame(window::Window) = begin
  scene = describe(describe(ui(window)), window.size)
  _scenes[objectid(window)] = scene
  ov = get(_overlay, objectid(window), nothing)
  tt = get(_tooltip, objectid(window), nothing)
  drawing(window, scene) do ctx, size, scene
    draw(ctx, size, scene)
    ov !== nothing && draw_menu(ctx, ov)
    tt !== nothing && draw_tooltip(ctx, tt)
  end
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

"Find the deepest SemanticUI node under the given position"
hittest(ui::ConcreteRect, (x, y)) = begin
  (x >= ui.left && x <= ui.left + ui.width &&
   y >= ui.top && y <= ui.top + ui.height) || return nothing
  for child in ui.children
    result = hittest(child, (x, y))
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

const _captured = Dict{UInt, SemanticUI}()

is_mouse_button(::KeyPress{K}) where K =
  K == Keys.mouse_left || K == Keys.mouse_right || K == Keys.mouse_middle
is_mouse_button(_) = false

onkey(w::Window, e) = begin
  id = objectid(w)
  ov = get(_overlay, id, nothing)
  if ov !== nothing && is_mouse_button(e)
    if e isa KeyPress{Keys.mouse_left} && ov.onselect !== nothing
      idx = menu_hittest(ov, w.mouse)
      ov.onselect(idx) # 0 if clicked outside
    end
    hide_menu!(w)
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
  end
end

onmouse(w::Window, e::MouseMove) = begin
  id = objectid(w)
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

export draw, ui, hittest, emit, show_menu!, hide_menu!, show_tooltip!, hide_tooltip!
