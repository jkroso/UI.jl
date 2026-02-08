# Text Wrapping
#
# The Text type supports automatic word wrapping during layout resolution.
# Text is configured with font family, size, color, line height, and wrap mode.

@use "../Interface/Descriptive"...
@use "../Interface/Specific"...
@use Colors: colorant

# Basic text with wrapping
# When text is placed in a Row alongside other elements, it wraps to fit
text_wrap = Row(width(400px), background("darkblue"),
  Row(width(min=100px, preferred=150px), height(100px), background("red")),
  Text("The quick brown fox jumps over the lazy dog. This text will automatically wrap to fit the available width."))

result = resolve(text_wrap, (400px, 200px))
text_result = result.children[2]
println("Text wrapped into $(length(text_result.lines)) lines:")
for (i, line) in enumerate(text_result.lines)
  println("  Line $i: \"$line\"")
end
println("Text dimensions: $(text_result.width) x $(text_result.height)")

# Styled text
styled_text = Column(width(300px), height(200px),
  padding(10px),
  background("white"),
  Text("Large Title", size=24pt, color=colorant"rgb(30,30,30)", family="Helvetica"),
  Text("Body text with different styling. Supports font family, size, color, and line height.",
       size=12pt, color=colorant"rgb(80,80,80)", family="Helvetica", lineheight=1.8em))

result = resolve(styled_text, (300px, 200px))
println("\nStyled text layout resolved:")
for (i, child) in enumerate(result.children)
  println("  Child $i: $(child.width) x $(child.height) at ($(child.left), $(child.top))")
end
