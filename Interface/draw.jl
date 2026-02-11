@use "github.com/jkroso/Prospects.jl" Field @def
@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont
@use "github.com/jkroso/MiniFB.jl"... int
@use GeometryBasics: Vec2
@use Colors: @colorant_str, RGBA
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
  rounded_rectangle(ctx, tl, sz, radius.tl, background=background.color,
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
  for (i, line) in enumerate(ui.lines)
    y = ui.top + ui.from.size * i
    text(ctx, (ui.left, y), f, ui.from.color, String(line))
  end
end

# Overlay system for floating menus
@def mutable struct MenuOverlay
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
show_menu!(window, items::Vector{String}, x, y, w; item_height=32px, onselect=nothing) = begin
  _overlay[objectid(window)] = MenuOverlay(items=items, x=x, y=y, width=w, item_height=item_height, onselect=onselect)
end

"Hide the floating menu overlay"
hide_menu!(window) = delete!(_overlay, objectid(window))

"Returns 1-based item index if pos is inside the menu, or 0 if outside"
menu_hittest(ov::MenuOverlay, (x, y)) = begin
  x < ov.x && return 0
  x > ov.x + ov.width && return 0
  y < ov.y && return 0
  total_height = ov.item_height * length(ov.items)
  y > ov.y + total_height && return 0
  clamp(Int(floor(int(y - ov.y) / int(ov.item_height))) + 1, 1, length(ov.items))
end

"Draw the menu overlay"
draw_menu(ctx, ov::MenuOverlay) = begin
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
  drawing(window, scene) do ctx, size, scene
    draw(ctx, size, scene)
    ov !== nothing && draw_menu(ctx, ov)
  end
end

Base.display(w::Window) = errormonitor(@async open(w))

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
    onkey(node, event)
    node = node.parent
    while node !== nothing && !(node isa SemanticUI)
      node = node.parent
    end
  end
end

emit(target::SemanticUI, event::MouseMove) = begin
  node = target
  while node !== nothing
    onmouse(node, event)
    node = node.parent
    while node !== nothing && !(node isa SemanticUI)
      node = node.parent
    end
  end
end

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

export draw, ui, hittest, emit, show_menu!, hide_menu!
