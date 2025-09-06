@use "github.com/jkroso/Prospects.jl" @property
@use "github.com/jkroso/MiniFB.jl/skia"...
@use "github.com/jkroso/MiniFB.jl"... int
@use "github.com/jkroso/Units.jl" mm ° Length
@use GeometryBasics: Vec2, Vec
@use "../Descriptive"... LayoutDirection
@use "../Specific"...
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
  grower = Rect(width(50mm),
                height(grow=GrowType.Grow),
                background("white"),
                border(2px, :solid, colorant"blue"),
                LayoutDirection.Column,
    Rect(width(grow=GrowType.Grow), height(20mm), background("green")),
    Rect(width(grow=GrowType.Grow), height(20mm), background("yellow")),
    Rect(width(grow=GrowType.Grow), height(20mm), background("red")))
  resolve(Rect(width(grow=GrowType.Grow),
               height(grow=GrowType.Grow),
               border(2px, :solid, colorant"blue"),
    grower), window.size)
end

draw_between(ctx, ui, left) = begin
  border = ui.from.border.between
  start = Vec2{px}(left+border.width/2, ui.top)
  finish = Vec2{px}(left+border.width/2, ui.top + ui.height)
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
  left = ui.left
  isfirst = true
  for child in ui.children
    draw(ctx, child.size, child)
    isfirst || draw_between(ctx, ui, left)
    isfirst = false
    left += child.width + ui.from.between_width
  end
end

r = ui(window)

errormonitor(@async open(window))
