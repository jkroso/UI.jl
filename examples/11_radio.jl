# Radio Group
#
# A set of radio buttons. Click to select one option.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/RadioGroup"...

@def mutable struct RadioExample <: SemanticUI end

describe((;firstchild)::RadioExample) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(20px),
      Alignment.Center,
      background("white"),
    Column(padding(8px),
      Box(height(24px), Text("Favorite color:", size=14pt, weight=700)),
      Box(width(4px), height(8px)),
      describe!(firstchild)))

const example = RadioExample(RadioGroup(labels=["Red", "Green", "Blue", "Yellow"], selected=1))

const window = Window(example, title="Radio Group", size=(260px, 210px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
