# Key Combos
#
# Display keyboard shortcuts with styled key caps.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe mixin! describe!
@use "../Interface/Semantic/KeyCombo" KeyCombo
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

@def mutable struct KeyComboDemo <: SemanticUI end

describe(::KeyComboDemo) = begin
  col = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(20px), background("white"),
               Box(height(20px),
                 Text("Keyboard Shortcuts", size=16pt, weight=700, color=colorant"rgb(30,30,30)")),
               Box(height(16px)))
  combos = [
    ("Save", KeyCombo(:S, :cmd)),
    ("Copy", KeyCombo(:C, :cmd)),
    ("Paste", KeyCombo(:V, :cmd)),
    ("Undo", KeyCombo(:Z, :cmd)),
    ("Find", KeyCombo(:F, :cmd)),
    ("Select All", KeyCombo(:A, :cmd)),
    ("Go to Line", KeyCombo(:G, :cmd, :ctrl)),
    ("Delete Line", KeyCombo(:Delete, :cmd, :shift)),
  ]
  for (label, combo) in combos
    mixin!(col, Row(width(grow=GrowType.Grow), height(32px), padding(8px, 0px),
      Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
        Text(label, size=13pt, color=colorant"rgb(80,80,80)")),
      describe!(combo)))
  end
  col
end

display(Window(KeyComboDemo(), title="Key Combos", size=(300px, 380px), animating=true))
