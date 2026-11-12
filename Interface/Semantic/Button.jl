@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "github.com/jkroso/MiniFB.jl" onkey KeyPress Keys
@use "../Geometric"...
@use "../abstract" SemanticUI describe describe! mixin! add_child! theme
@use "../draw" ishovered cursor
@use Colors: @colorant_str

export Button, ButtonGroup

"A button. Clicking it calls `onclick(button)` when one is given."
@def mutable struct Button <: SemanticUI
  label::String = ""
  onclick::Any = nothing
end
Button(label::String; kwargs...) = Button(;label=label, kwargs...)
Button(child::SemanticUI; kwargs...) = begin
  b = Button(;kwargs...)
  add_child!(b, child)
  b
end

@def mutable struct ButtonGroup <: SemanticUI end

function describe(b::Button)
  content = if b.firstchild isa SemanticUI
    describe!(b.firstchild)
  else
    Text(b.label, size=12pt, weight=600, align=TextAlign.Center)
  end
  Box(padding(6px, 4px), radius(6px),
      background(ishovered(b) ? theme(b).hover : theme(b).surface),
      border(1px, :solid, theme(b).line),
      Alignment.Center,
      content)
end

onkey(b::Button, ::KeyPress{Keys.mouse_left}) = b.onclick === nothing || b.onclick(b)
cursor(::Button) = :hand

function describe(b::ButtonGroup)
  Row(border(1px, :solid, theme(b).line),
    (describe!(c) for c in b.children)...)
end
