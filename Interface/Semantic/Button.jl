@use "github.com/jkroso/Prospects.jl" @def
@use "../Geometric"...
@use "../abstract" SemanticUI Text describe UI

export Button, ButtonGroup

@def mutable struct Button <: SemanticUI
  label::String
end
Button(label) = Button(label=label)
@def mutable struct ButtonGroup <: SemanticUI end

function describe(b::Button)
  Rect(padding(5mm, 8mm),
       background("#fff"),
       border(1px, :solid, "#e5e7eb"),
    Text(b.label, size=12mm, weight=600, color=rgb(17, 24, 39)))
end

function describe(b::ButtonGroup)
  Rect(border(1px, :solid, "#e5e7eb", between_children=true),
       layout(:row),
    (describe(c) for c in b.children)...)
end

