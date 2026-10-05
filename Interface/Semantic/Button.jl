@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "github.com/jkroso/MiniFB.jl" onkey KeyPress Keys
@use "../Geometric"...
@use "../abstract" SemanticUI describe describe! mixin! add_child!
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
    Text(b.label, size=12pt, weight=600, color=colorant"rgb(17,24,39)", align=TextAlign.Center)
  end
  Box(padding(6px, 4px), radius(6px),
      background(ishovered(b) ? colorant"rgb(243,244,246)" : colorant"white"),
      border(1px, :solid, colorant"rgb(229,231,235)"),
      Alignment.Center,
      content)
end

onkey(b::Button, ::KeyPress{Keys.mouse_left}) = b.onclick === nothing || b.onclick(b)
cursor(::Button) = :hand

function describe(b::ButtonGroup)
  Row(border(1px, :solid, colorant"rgb(229,231,235)"),
    (describe!(c) for c in b.children)...)
end
