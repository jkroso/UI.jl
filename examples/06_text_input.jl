# Text Input
#
# A text input with cursor, selection, and mouse interaction.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "github.com/jkroso/Font.jl/units" em
@use "../Interface/Descriptive"...
@use "../Interface/draw" ui
@use "../Interface/abstract" ConceptualUI focus describe
@use "../Interface/TextInput"...

@def mutable struct Example <: ConceptualUI end

describe(e::Example) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(1em),
      Alignment.Center,
      background("white"),
    describe(e.firstchild))

const input = TextInput(placeholder="Type here...")
const window = Window(Example(input), title="Text Input", size=(400px, 80px), animating=true)
focus(input)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
