# Slider
#
# A draggable slider that updates a displayed value.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/Slider"...

@def mutable struct SliderExample <: SemanticUI end

describe((;firstchild)::SliderExample) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(20px),
      Alignment.Center,
      background("white"),
    Column(width(grow=GrowType.Grow), padding(10px),
      Box(width(grow=GrowType.Grow), height(24px),
        Text("Value: $(round(firstchild.value, digits=2))", size=14pt)),
      Box(width(4px), height(10px)),
      describe!(firstchild)))

const example = SliderExample(Slider(value=0.3))

const window = Window(example, title="Slider", size=(350px, 120px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
