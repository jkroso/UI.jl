@use "github.com/jkroso/Prospects.jl" Field
@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont
@use "github.com/jkroso/MiniFB.jl"... int
@use GeometryBasics: Vec2
@use "./abstract" describe Root UITree
@use "./Descriptive"...
@use "./Specific"...

draw_between_row(ctx, ui, left) = begin
  border = ui.from.border.between
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
frame(window::Window) = drawing(draw, window, describe(describe(ui(window)), window.size))
Base.display(w::Window) = errormonitor(@async open(w))

export draw, ui
