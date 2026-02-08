@use "github.com/jkroso/Prospects.jl" @property
@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont
@use "github.com/jkroso/MiniFB.jl"... int
@use "github.com/jkroso/Units.jl" mm ° Length
@use GeometryBasics: Vec2, Vec
@use "./Descriptive"...
@use "./Specific"...
@use Colors...

window = Window(title="test", size=(150mm, 150mm), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

frame(window::Window) = drawing(draw, window, ui(window))

# ui(window) = begin
#   (w,h) = window.size
#   grower = Rect(width(w),
#                 height(h),
#                 background(colorant"rgb(45,48,53)"),
#                 border(6px, :solid, colorant"rgb(100,100,255)"),
#     Rect(width(min=300px, grow=GrowType.Grow),
#          background("transparent"),
#          radius(2mm),
#          border(2px, :solid, colorant"rgb(255,255,255)", between=true),
#       Rect(width(grow=GrowType.Grow), height(50mm), background("yellow"), border(8px, :solid, colorant"rgb(0,200,30)"), radius(2mm)),
#       Rect(width(grow=GrowType.Grow), height(50mm), background("white"), border(2px, :solid, colorant"rgb(70,30,200)"), LayoutDirection.Column,
#         Rect(width(20mm), height(20mm), background("green")),
#         Rect(width(20mm), height(20mm), background("yellow")),
#         Rect(width(20mm), height(20mm), background("red"))),
#       Rect(width(25mm), height(50mm), background("lightblue"), border(2px, :solid, colorant"rgb(155,30,30)"))))
#   resolve(grower, window.size)
# end

ui(window) = begin
  (w,h) = window.size
  grower = Column(width(50mm), border(1px, :solid, colorant"rgb(150,150,150)", between=true), radius(3px),  background(colorant"white"),
    Box(width(grow=GrowType.Grow), height(31px), Text("Copy", size=16px, family="Helvetica", color=colorant"rgb(80,80,80)")),
    Box(width(grow=GrowType.Grow), height(31px), Text("Paste")),
    Box(width(grow=GrowType.Grow), height(31px), Text("Edit")))
  resolve(Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Center, background(colorant"white"), grower), window.size)
end

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
  size = ui.size.-bw

  rounded_rectangle(ctx, tl, size, radius.tl, background=background.color,
                                              color=border.top.color,
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
end

draw(ctx, _, ui::ConcreteText) = begin
  (;size,family)=ui.from
  font = SkiaFont(family, size)
  text(ctx, (ui.left, ui.top+size/2), font, ui.from.color, ui.words[1])
end

r = ui(window)
errormonitor(@async open(window))
