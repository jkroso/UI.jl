@use "github.com/jkroso/Prospects.jl" @property
@use "github.com/jkroso/MiniFB.jl/cairo"...
@use "github.com/jkroso/MiniFB.jl"...
@use "github.com/jkroso/Units.jl" mm
@use "../Descriptive"... BorderSide
@use GeometryBasics: Vec2
@use "../Specific"...
@use Colors...

window = Window(title="test", size=(150mm, 150mm), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)
frame(w::Window) = begin
  ui(w)
  w.buffer
end

ui(window) = begin
  (w,h) = window.size
  grower = Rect(width(w), height(h), background(colorant"rgb(45,48,53)"),
    Rect(width(100px), height(100px), background("red")),
    Rect(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
    Rect(width(grow=GrowType.Grow), height(100px), background("yellow")),
    Rect(width(100px), height(100px), background("lightblue")))
  concrete = resolve(grower, (w,h))
  # drawing(draw, window, concrete)
end
c = ui(window)

@property ConcreteRect.origin = Vec2{px}(self.left, self.top)
@property ConcreteRect.background_color = self.from.background.color
@property ConcreteRect.corners = begin
  tl = self.origin
  tr = Vec2{px}(tl[1]+self.width, tl[2])
  br = Vec2{px}(tl[1]+self.width, tl[2]+self.height)
  bl = Vec2{px}(tl[1], tl[2]+self.height)
  (tl, tr, br, bl)
end
@property ConcreteRect.border_colors = begin
end
@property ConcreteRect.border_widths = begin
end

draw(ctx, size, ui::ConcreteRect) = begin
  centers = ui.corner_centers
  colors = ui.border_colors
  widths = ui.border_widths
  radii = ui.radii
  path(ctx, color=colors[1], width=widths[1])
  arc(ctx, centers[1], radii[1], -90°, 0°)
  path(ctx, color=colors[2], width=widths[2])
  arc(ctx, centers[2], radius, 0°, 90°)
  path(ctx, color=colors[3], width=widths[3])
  arc(ctx, centers[3], radius, 90°, 180°)
  path(ctx, color=colors[4], width=widths[4])
  arc(ctx, centers[4], radius, 180°, 270°)
  close_path(ctx, background=ui.background_color)
end

errormonitor(@async open(window))
