# Color Picker
#
# Click and drag on the shade area to pick saturation/value.
# Click and drag on the hue bar to change the hue.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/ColorPicker" ColorPicker
@use Colors: @colorant_str, HSV

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

@def mutable struct PickerDemo <: SemanticUI end

describe(demo::PickerDemo) =
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Alignment.Center, background(colorant"rgb(245,245,248)"),
    describe!(demo.firstchild))

const example = PickerDemo(ColorPicker(color=HSV(225, 0.8, 0.8)))

display(Window(example, title="Color Picker", size=(280px, 380px), animating=true))
