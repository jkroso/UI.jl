# Centering Text in a Circle
#
# A Box defaults to Alignment.Center, so its single child is centered both
# horizontally and vertically. Setting radius to half the Box's size turns
# the rounded rectangle into a circle. Text height is cap_height, so a digit
# placed inside a centered Box visually centers on the cap area of the glyph.

@use "github.com/jkroso/MiniFB.jl/skia"...
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/draw" draw ui
@use Colors: @colorant_str

const window = Window(title="Centered Numbers", size=(340px, 120px))
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

ui(window) =
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
    background(colorant"rgb(240,240,240)"),
    Row(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(20px),
      Box(width(80px), height(80px), radius(40px), background("steelblue"),
        Text("1", size=32pt, weight=600, color=colorant"white", align=TextAlign.Center)),
      Box(width(80px), height(80px), radius(40px), background("coral"),
        Text("2", size=32pt, weight=600, color=colorant"white", align=TextAlign.Center)),
      Box(width(80px), height(80px), radius(40px), background("mediumseagreen"),
        Text("3", size=32pt, weight=600, color=colorant"white", align=TextAlign.Center))))

display(window)
