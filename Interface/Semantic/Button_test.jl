@use Test: @test
@use "github.com/jkroso/Font.jl/units" px
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "github.com/jkroso/Prospects.jl" @def
@use "../abstract" SemanticUI describe theme
@use "../Geometric"...
@use "../draw" frame rect
@use "../testing" click! move!
@use "./Button" Button BUTTON_H darker pressed
@use "./RadioGroup" RadioGroup

@def mutable struct Bar <: SemanticUI end
describe(b::Bar) = Row(width(400px), height(60px), child_gap=8px, b.children...)

"The colour behind a node, from the box that its `describe` made"
fill(node) = getfield(rect(node).from.background, 1)

let clicks = Ref(0), plain = Button("Look", onclick=_ -> clicks[] += 1), main = Button(label="Connect", primary=true),
    choices = RadioGroup(labels=["One", "Two"]), w = Window(Bar(plain, main, choices), size=(400px, 60px))
  frame(w)
  # A button is as high as a bar of choices, so the two sit well side by side
  @test rect(plain).height == BUTTON_H == rect(choices).height && rect(main).height == BUTTON_H
  # A plain button has the colour that components put text on. The main one is filled with the accent.
  @test fill(plain) == theme(plain).surface && fill(main) == theme(main).accent
  # The mouse over a button changes its colour
  move!(w, plain)
  @test fill(plain) == theme(plain).hover && !pressed(plain)
  move!(w, main)
  @test fill(main) == darker(theme(main).accent, 0.09) && fill(plain) == theme(plain).surface
  # A click calls `onclick` once
  click!(w, plain)
  @test clicks[] == 1
  # While the mouse button is down on it, a button is darker
  w.keys |= Keys.mouse_left
  frame(w)
  @test pressed(plain) && fill(plain) == theme(plain).line
  w.keys ⊻= Keys.mouse_left
  frame(w)
  @test !pressed(plain) && fill(plain) == theme(plain).hover
end
