@use "github.com/jkroso/Prospects.jl" @property
@use "github.com/jkroso/MiniFB.jl/cairo"... int
@use "github.com/jkroso/MiniFB.jl"...
@use "github.com/jkroso/Units.jl" mm ° Length
@use "../Descriptive"...
@use GeometryBasics: Vec2, Vec
@use "../Specific"... polarity
@use Colors...
@use Cairo

window = Window(title="test", size=(150mm, 150mm), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

frame(window::Window) = drawing(draw, window, ui(window))

ui(window) = begin
  (w,h) = window.size
  grower = Rect(width(w),
                height(h),
                background(colorant"rgb(45,48,53)"),
                # border(1.2mm, :solid, colorant"rgb(255,255,255)"),
                radius(3mm),
    Rect(width(min=300px, grow=GrowType.Grow),
         background("transparent"),
         radius(2mm),
         border(2px, :solid, colorant"rgb(255,255,255)", between=true),
      Rect(width(grow=GrowType.Grow), height(25mm), background("yellow"), border(1mm, :solid, colorant"rgb(155,30,30)")),
      Rect(width(grow=GrowType.Grow), height(25mm), background("purple"), border(1mm, :solid, colorant"rgb(155,30,30)")),
      Rect(width(25mm), height(25mm), background("lightblue"), border(1mm, :solid, colorant"rgb(155,30,30)"))))
  resolve(grower, window.size)
end

const start_angles = [225°:270°, 315°:0°, 45°:90°, 135°:180°]
const stop_angles = [270°:315°, 0°:45°, 90°:135°, 180°:225°]

draw_side(ctx, ui, c1, c2) = begin
  widths = ui.border_widths
  centers = ui.centers
  radii = ui.radii
  Cairo.new_path(ctx)
  a1 = start_angles[c1]
  a2 = stop_angles[c1]
  lw = widths[c1]
  set_color(ctx, ui.border_colors[c1])
  Cairo.set_line_width(ctx, int(lw))
  arc(ctx, centers[c1] + (lw/2)*polarity[c1], radii[c1], a1.start, a1.stop)
  line_end = ui.corners[c2] + (Vec2(widths[4]/2, radii[1]+widths[4]),
                               Vec2(-radii[2] - widths[1], widths[1]/2),
                               Vec2(-widths[2]/2, -radii[3]-widths[2]),
                               Vec2(radii[4]+widths[3], -widths[3]/2))[c2]
  line_to(ctx, line_end)
  arc(ctx, centers[c2] + (lw/2)*polarity[c2], radii[c2], a2.start, a2.stop)
  # Cairo.set_line_cap(ctx, 0)
  Cairo.stroke_transformed(ctx)
end

draw_background(ctx, ui::ConcreteRect) = begin
  (;radii,centers,border_widths,from) = ui
  path(ctx, background=from.background.color) do
    arc(ctx, centers[1], radii[1]-2border_widths[1], 180°, 270°)
    arc(ctx, centers[2], radii[2]-2border_widths[2], 270°, 0°)
    arc(ctx, centers[3], radii[3]-2border_widths[3], 0°, 90°)
    arc(ctx, centers[4], radii[4]-2border_widths[4], 90°, 180°)
  end
end

line(ctx, start, finish, width=0px, color=colorant"black") = begin
  Cairo.new_path(ctx)
  set_color(ctx, color)
  Cairo.set_line_width(ctx, int(width))
  Cairo.move_to(ctx, int(start[1]), int(start[2]))
  Cairo.line_to(ctx, int(finish[1]), int(finish[2]))
  Cairo.stroke_transformed(ctx)
end

draw_between(ctx, ui, left) = begin
  border = ui.from.border.between
  start = Vec2{px}(left+border.width/2, ui.top)
  finish = Vec2{px}(left+border.width/2, ui.top + ui.height)
  line(ctx, start, finish, border.width, border.color)
end

draw(ctx, size, ui::ConcreteRect) = begin
  Cairo.save(ctx)
  draw_side(ctx, ui, 1, 2)
  draw_side(ctx, ui, 2, 3)
  draw_side(ctx, ui, 3, 4)
  draw_side(ctx, ui, 4, 1)
  draw_background(ctx, ui)
  Cairo.clip(ctx)
  isfirst = true
  left = ui.left
  for child in ui.children
    if !isfirst
      draw_between(ctx, ui, left)
    end
    isfirst = false
    left += child.width + ui.from.between_width
    draw(ctx, child.size, child)
  end
  Cairo.restore(ctx)
end

ui(window)

errormonitor(@async open(window))
