# Data Inspector
#
# An interactive viewer/editor for Julia data structures.
# Click chevrons to expand/collapse. Click leaf values to edit.
# Bool values toggle on click. Press Enter to commit, Escape to cancel.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe! focus
@use "../Interface/Semantic/Inspector" Inspector inspect
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

@def mutable struct Demo <: SemanticUI end

describe(demo::Demo) =
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(20px), Alignment.Start,
    background(colorant"rgb(245,245,248)"),
    Column(width(400px), Alignment.Start,
      Box(height(24px), Text("Data Inspector", size=14pt, weight=700, color=colorant"rgb(30,30,30)")),
      Box(height(8px)),
      describe!(demo.firstchild)))

const data = Dict{String,Any}(
  "name" => "Alice",
  "age" => 30,
  "active" => true,
  "scores" => [95, 87, 92],
  "address" => Dict{String,Any}(
    "city" => "Portland",
    "zip" => 97201
  ),
  "tags" => (:julia, :ui, :inspector),
  "nothing_val" => nothing
)

const inspector = Inspector(inspect(data, label="data"))
const window = Window(Demo(inspector), title="Data Inspector", size=(500px, 600px), animating=true)
focus(inspector)

display(window)
