# Checkbox
#
# Interactive checkboxes. Click to toggle checked state.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/Checkbox"...

@def mutable struct Example <: SemanticUI end

describe(e::Example) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(20px),
      Alignment.Center,
      background("white"),
    Column(padding(8px), map(describe!, e.children)...))

const example = Example(Checkbox(label="Enable notifications"),
                        Checkbox(label="Dark mode", checked=true),
                        Checkbox(label="Auto-save"))

const window = Window(example, title="Checkboxes", size=(300px, 160px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
