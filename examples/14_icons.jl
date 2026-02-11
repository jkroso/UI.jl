# Icons
#
# Display icons from the Icons folder using the Icon component.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/Icon"...
@use "../Interface/Semantic/SVG"...
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

@def mutable struct IconExample <: SemanticUI end

describe(::IconExample) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(20px),
      Alignment.Center,
      background("white"),
    Column(padding(12px),
      Row(padding(8px),
        describe!(Icon(name="house", color=colorant"rgb(30,30,30)", size=24px)),
        Box(width(16px)),
        describe!(Icon(name="gear", color=colorant"rgb(30,30,30)", size=24px)),
        Box(width(16px)),
        describe!(Icon(name="search", color=colorant"rgb(59,130,246)", size=24px)),
        Box(width(16px)),
        describe!(Icon(name="heart-fill", color=colorant"rgb(220,50,50)", size=24px)),
        Box(width(16px)),
        describe!(Icon(name="star-fill", color=colorant"rgb(250,180,30)", size=24px))),
      Box(height(12px)),
      Row(padding(8px),
        describe!(Icon(name="envelope", color=colorant"rgb(30,30,30)", size=32px)),
        Box(width(16px)),
        describe!(Icon(name="bell", color=colorant"rgb(30,30,30)", size=32px)),
        Box(width(16px)),
        describe!(Icon(name="person", color=colorant"rgb(30,30,30)", size=32px)),
        Box(width(16px)),
        describe!(Icon(name="trash", color=colorant"rgb(220,50,50)", size=32px)),
        Box(width(16px)),
        describe!(Icon(name="check-circle-fill", color=colorant"rgb(34,197,94)", size=32px)))))

display(Window(IconExample(), title="Icons", size=(350px, 180px), animating=true))
