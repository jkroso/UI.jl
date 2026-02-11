# Text Wrapping
#
# The Text type supports automatic word wrapping during layout resolution.
# Text is configured with font family, size, color, line height, and wrap mode.
# Text must be placed inside a Box container for layout.

@use "github.com/jkroso/Font.jl/units" em
@use "../Interface/Descriptive"...
@use "../Interface/Specific"...
@use Colors: @colorant_str

# Basic text with wrapping
# Text is wrapped in a Box; the Box gets sized by its parent, and the text wraps to fit
text_wrap = Column(width(400px), height(200px), background("darkblue"),
  Row(width(380px), height(40px), background("red")),
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
    Text("The quick brown fox jumps over the lazy dog. This text will automatically wrap to fit the available width.")))

result = resolve(text_wrap, (400px, 200px))
text_result = result.children[2].children[1]
println("Text wrapped into $(length(text_result.lines)) lines:")
for (i, line) in enumerate(text_result.lines)
  println("  Line $i: \"$line\"")
end
println("Text dimensions: $(text_result.width) x $(text_result.height)")

# Styled text in boxes
styled_text = Column(width(300px), height(200px),
  padding(10px),
  background("white"),
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
    Text("Large Title", size=24pt, color=colorant"rgb(30,30,30)", family="Helvetica")),
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
    Text("Body text with different styling. Supports font family, size, color, and line height.",
         size=12pt, color=colorant"rgb(80,80,80)", family="Helvetica", lineheight=1.8em)))

result = resolve(styled_text, (300px, 200px))
println("\nStyled text layout resolved:")
for (i, child) in enumerate(result.children)
  println("  Child $i: $(child.width) x $(child.height) at ($(child.left), $(child.top))")
end

# Compose into a scene
# Expected result: two sections on a light gray background
#   1. A dark blue column with a red bar at top and wrapped white text below
#   2. A white card with a large title line and smaller body text below it
scene = Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), background(colorant"rgb(240,240,240)"),
  Column(width(320px), height(grow=GrowType.Grow), padding(10px),
    Column(width(300px), height(100px), background("darkblue"),
      Row(width(280px), height(30px), background("red")),
      Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
        Text("The quick brown fox jumps over the lazy dog. This text wraps to fit.",
             color=colorant"white"))),
    Column(width(300px), height(140px), padding(10px), background("white"),
      Box(width(grow=GrowType.Grow), height(40px),
        Text("Large Title", size=24pt, color=colorant"rgb(30,30,30)", family="Helvetica")),
      Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
        Text("Body text with different styling. Supports font family, size, color, and line height.",
             size=12pt, color=colorant"rgb(80,80,80)", family="Helvetica", lineheight=1.8em)))))

@use "../Interface/save" save_scene
save_scene(@__DIR__()*"/04_text_wrapping.png", scene, (340px, 280px))
