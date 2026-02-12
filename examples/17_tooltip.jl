# Tooltip
#
# Hover over buttons to see tooltips with rich content.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe mixin! add_child! describe!
@use "../Interface/Semantic/Tooltip" Tooltip
@use "../Interface/Semantic/Icon" Icon
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

const white = colorant"rgb(240,240,240)"

tip(icon, label) =
  Row(height(20px), Alignment.Center, padding(10px),
    describe!(Icon(icon, color=white, size=14px)),
    Box(padding(10px), Text(label, size=12pt, color=white)))

@def mutable struct TooltipDemo <: SemanticUI end

describe(tt::TooltipDemo) = begin
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(40px), Alignment.Center, background(colorant"rgb(245,245,248)"),
    Box(Text("Hover over buttons to see tooltips", size=12pt, color=colorant"rgb(100,100,100)")),
    Box(height(12px)),
    (Row(padding(8px), describe!(child)) for child in tt.children)...)
end

const example = TooltipDemo(
  Tooltip("Top",    tip("arrow-up", "Tooltip on top"),       placement=:top),
  Tooltip("Bottom", tip("arrow-down", "Tooltip below"),      placement=:bottom),
  Tooltip("Left",   tip("arrow-left", "Tooltip on left"),    placement=:left),
  Tooltip("Right",  tip("arrow-right", "Tooltip on right"),  placement=:right))

display(Window(example, title="Tooltips", size=(500px, 600px), animating=true))
