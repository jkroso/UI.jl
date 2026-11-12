# Nodes that a document can show. A code block in the language `ui` loads this
# file, makes one of these and the page shows it. See welcome.md.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey
@use "github.com/jkroso/Font.jl/units" px
@use "../../Interface/Geometric"...
@use "../../Interface/abstract" SemanticUI describe
@use "../../Interface/draw" ishovered cursor
@use Colors: @colorant_str

"A button that counts the times you click it"
@def mutable struct Counter <: SemanticUI
  count::Int = 0
end

describe(c::Counter) =
  Box(padding(16px, 8px), radius(6px), background(ishovered(c) ? colorant"rgb(150,84,40)" : colorant"rgb(176,100,48)"),
    Text(c.count == 1 ? "Clicked 1 time" : "Clicked $(c.count) times", size=15px, family="Helvetica", color=colorant"white"))

cursor(::Counter) = :hand
onkey(c::Counter, ::KeyPress{Keys.mouse_left}) = c.count += 1

"A bar that shows how much of something is done, from 0 to 1"
@def mutable struct Meter <: SemanticUI
  done::Float64 = 0.5
  label::String = ""
end

describe(m::Meter) =
  Row(width(grow=GrowType.Grow), child_gap=12px, Alignment.Center,
    Box(width(grow=GrowType.Grow), height(10px), radius(5px), background(colorant"rgba(120,100,80,0.25)"), Alignment.Start,
      Box(width(percent=clamp(m.done, 0, 1)), height(10px), radius(5px), background(colorant"rgb(176,100,48)"))),
    Box(Text(isempty(m.label) ? "$(round(Int, 100m.done))%" : m.label, size=14px, family="Helvetica", color=colorant"rgb(140,120,100)")))
