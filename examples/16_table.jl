# Table
#
# Display a table with headers and rows.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe mixin! describe!
@use "../Interface/Semantic/Table" Table TableHeader TableRow
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

@def mutable struct TableDemo <: SemanticUI end

const example = Table(
  TableHeader("Product", "Color", "Category", "Price"),
  TableRow("MacBook Pro 17\"", "Silver", "Laptop", "\$2999"),
  TableRow("Surface Pro", "White", "Laptop", "\$1999"),
  TableRow("Magic Mouse 2", "Black", "Accessories", "\$99"),
  TableRow("iPad Air", "Blue", "Tablet", "\$599"),
  TableRow("AirPods Pro", "White", "Audio", "\$249"))

describe((;firstchild)::TableDemo) = begin
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      padding(20px), Alignment.Center, background(colorant"rgb(245,245,248)"), describe!(firstchild))
end

display(Window(example, title="Table", size=(550px, 300px), animating=true))
