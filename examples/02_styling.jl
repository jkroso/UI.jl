# Styling
#
# Containers support rich styling: backgrounds, borders, padding, and radius.
# These are applied as positional arguments using helper functions.

@use "../Interface/Descriptive"...
@use "../Interface/Specific"...
@use Colors: @colorant_str

# Backgrounds - pass any CSS color name or hex string
colored_boxes = Row(width(400px), height(100px),
  Row(width(100px), height(80px), background("coral")),
  Row(width(100px), height(80px), background("steelblue")),
  Row(width(100px), height(80px), background("#9b59b6")))

# Borders - border(width, style, color)
bordered = Box(width(200px), height(100px),
  border(2px, :solid, "red"),
  background("white"),
  Row(width(180px), height(80px), background("lightyellow")))

# Selective borders - use bracket indexing for specific sides
top_border_only = border(2px, :solid, colorant"rgb(100,100,255)")[:top]

# Padding - padding(all) or padding(horizontal, vertical)
padded = Column(width(300px), height(200px),
  padding(10px),
  background("white"),
  border(1px, :solid, "gray"),
  Row(width(100px), height(50px), background("lightblue")),
  Row(width(100px), height(50px), background("lightcoral")))

# Radius - rounded corners
rounded = Box(width(200px), height(100px),
  radius(8px),
  background("steelblue"),
  border(2px, :solid, "navy"))

# Combining it all: a card-like component
card = Box(width(300px), height(150px),
  padding(12px),
  radius(6px),
  background("white"),
  border(1px, :solid, "#e5e7eb"),
  Column(width(276px), height(126px),
    Text("Card Title", size=16pt, color=colorant"rgb(30,30,30)"),
    Text("Some descriptive text that goes below the title.",
         size=11pt, color=colorant"rgb(100,100,100)")))

# Compose all examples into a single layout for display
scene = Box(
  width(grow=GrowType.Grow),
  height(grow=GrowType.Grow),
  background(colorant"rgb(240,240,240)"),
  Column(width(420px), height(grow=GrowType.Grow), padding(10px),
    colored_boxes,
    bordered,
    padded,
    rounded,
    card))

# --- Render in a window ---
@use "github.com/jkroso/MiniFB.jl/skia"... SkiaFont
@use "github.com/jkroso/MiniFB.jl"... int
@use "github.com/jkroso/Units.jl" mm
@use GeometryBasics: Vec2

window = Window(title="Styling Example", size=(120mm, 200mm), animating=false)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

draw(ctx, size, ui::ConcreteRect) = begin
  (;background, border, radius) = ui.from
  bw = border.top.width
  tl = ui.origin .+ bw/2
  sz = ui.size .- bw
  rounded_rectangle(ctx, tl, sz, radius.tl, background=background.color,
                                             color=border.top.color,
                                             stroke_width=bw)
  isfirst = true
  if ui.from isa Row
    left = ui.left
    for child in ui.children
      draw(ctx, child.size, child)
      isfirst = false
      left += child.width + ui.from.between_width
    end
  else
    top = ui.top
    for child in ui.children
      draw(ctx, child.size, child)
      isfirst = false
      top += child.height + ui.from.between_width
    end
  end
end

draw(ctx, _, ui::ConcreteText) = begin
  f = SkiaFont(ui.from.family, ui.from.size)
  for (i, line) in enumerate(ui.lines)
    y = ui.top + ui.from.size * i
    text(ctx, (ui.left, y), f, ui.from.color, String(line))
  end
end

frame(w::Window) = drawing(draw, w, resolve(scene, w.size))

errormonitor(@async open(window))
