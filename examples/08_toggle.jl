# Toggle
#
# Toggle switches. Click to switch on/off.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/Toggle"...

@def mutable struct Example <: SemanticUI end

describe(e::Example) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(20px),
      Alignment.Center,
      background("white"),
    Column(padding(8px),
      Row(height(30px), padding(2px),
        describe!(e.children[1]),
        Box(width(10px), height(24px)),
        Box(height(24px), Text("Wi-Fi", size=13pt))),
      Row(height(30px), padding(2px),
        describe!(e.children[2]),
        Box(width(10px), height(24px)),
        Box(height(24px), Text("Bluetooth", size=13pt))),
      Row(height(30px), padding(2px),
        describe!(e.children[3]),
        Box(width(10px), height(24px)),
        Box(height(24px), Text("Airplane Mode", size=13pt)))))

const example = Example(Toggle(on=true), Toggle(on=false), Toggle(on=false))

const window = Window(example, title="Toggles", size=(280px, 170px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
