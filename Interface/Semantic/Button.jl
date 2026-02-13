@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../abstract" SemanticUI describe describe! mixin! add_child!
@use Colors: @colorant_str

export Button, ButtonGroup

@def mutable struct Button <: SemanticUI
  label::String = ""
end
Button(label::String) = Button(label=label)
Button(child::SemanticUI) = begin
  b = Button()
  add_child!(b, child)
  b
end

@def mutable struct ButtonGroup <: SemanticUI end

function describe(b::Button)
  content = if b.firstchild isa SemanticUI
    describe!(b.firstchild)
  else
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
        Text(b.label, size=12pt, weight=600, color=colorant"rgb(17,24,39)"))
  end
  Box(padding(6px, 4px), radius(6px),
      background(colorant"white"),
      border(1px, :solid, colorant"rgb(229,231,235)"),
      Alignment.Center,
      content)
end

function describe(b::ButtonGroup)
  Row(border(1px, :solid, colorant"rgb(229,231,235)"),
    (describe!(c) for c in b.children)...)
end
