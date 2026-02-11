@use "github.com/jkroso/Prospects.jl" @def
@use "../Descriptive"...
@use "../abstract" ConceptualUI Text describe UI

export Button, ButtonGroup

@def mutable struct Button <: ConceptualUI
  label::String
end
Button(label) = Button(label=label)
@def mutable struct ButtonGroup <: ConceptualUI end

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

d = describe(Button("Click here"))
# describe(ButtonGroup(Button("Click here")))
# describe(ButtonGroup(Button("Click here"), Button("Or here")))

r = describe(d, (width=800px, height=600px))



display(r)
