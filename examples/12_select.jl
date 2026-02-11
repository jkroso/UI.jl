# Select (Dropdown)
#
# A dropdown select. Click to open menu, click item to select.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/Dropdown"...

@def mutable struct SelectExample <: SemanticUI end

describe((;firstchild)::SelectExample) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(20px),
      Alignment.Start,
      background("white"),
    Column(width(200px), padding(8px), Alignment.Start,
      Box(height(24px), Text("Choose a fruit:", size=14pt, weight=700)),
      Box(width(4px), height(8px)),
      describe!(firstchild)))

const example = SelectExample(Dropdown(options=["Apple", "Banana", "Cherry", "Date", "Elderberry"]))

const window = Window(example, title="Select", size=(280px, 400px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
