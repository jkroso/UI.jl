@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! theme scale handled integrate inputs sized
@use "../draw" cursor
@use "./Icon" Icon
@use Colors: @colorant_str

@def mutable struct Select <: SemanticUI
  selected::Int = 1
  options::Vector{String} = String[]
end

current_label(s::Select) = isempty(s.options) ? "" : s.options[clamp(s.selected, 1, length(s.options))]

describe(s::Select) = begin
  k = scale(theme(s))
  Row(width(grow=GrowType.Grow), height(36px * k),
    padding(8px * k),
    border(1px, :solid, theme(s).line),
    radius(4px),
    background(theme(s).surface),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Text(current_label(s), size=sized(13pt, theme(s)))),
    # The arrow is the same thin one a tree has
    Box(width(20px * k), height(grow=GrowType.Grow), Alignment.Center,
      describe!(Icon("chevron-down", size=12px * k, color=theme(s).dim))))
end

cursor(::Select) = :hand

onkey(s::Select, ::KeyPress{Keys.mouse_left}) = begin
  isempty(s.options) && return
  s.selected = mod1(s.selected + 1, length(s.options))
  handled
end

"The option that's chosen, or `nothing` when there are no options"
integrate(s::Select) = isempty(s.options) ? nothing : current_label(s)

# What `describe` reads, so that it only runs again when one of these changes
inputs(s::Select) = (s.selected, s.options)

export Select
