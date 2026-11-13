@use Test: @test
@use "github.com/jkroso/Font.jl/units" px
@use "github.com/jkroso/MiniFB.jl" Window KeyPress Keys Typed onkey ontype
@use "github.com/jkroso/Prospects.jl" @def
@use "../abstract" SemanticUI describe integrate focus handled
@use "../Geometric"...
@use "../draw" frame clipboard clipboard! emit
@use "./TextInput" TextInput text_view width_to
@use GeometryBasics: Vec2

# A layout is made once. A semantic node around the field has it described again on each frame.
@def mutable struct Form <: SemanticUI end
describe(f::Form) = Box(width(140px), height(40px), f.firstchild)

let input = TextInput(), w = Window(Form(input), size=(140px, 40px))
  frame(w)
  focus(input)
  press(k, mods...) = (foreach(m -> w.keys |= m, mods); onkey(w, KeyPress{k}(0, w)); foreach(m -> w.keys ⊻= m, mods); frame(w))
  type(s) = (foreach(c -> ontype(w, Typed(c, w)), s); frame(w))

  # It takes the characters the keyboard types, whatever they are
  type("Is it é?")
  @test integrate(input) == "Is it é?"
  # A window that isn't open types what a US keyboard would
  press(Keys.slash, Keys.shft)
  @test input.text == "Is it é??"
  press(Keys.backspace)
  @test input.text == "Is it é?"

  # Home and End, and Option with an arrow to move by a word
  press(Keys.home); type("> ")
  @test input.text == "> Is it é?"
  press(Keys._end); press(Keys.left, Keys.opt, Keys.shft)
  @test (input.anchor, input.cursor) == (10, 8)

  # Copy, cut and paste
  press(Keys.c, Keys.cmd)
  @test clipboard(w) == "é?"
  press(Keys.a, Keys.cmd); press(Keys.x, Keys.cmd)
  @test input.text == "" && clipboard(w) == "> Is it é?"
  clipboard!(w, "two\nlines"); press(Keys.v, Keys.cmd)
  @test input.text == "two lines"

  # Text that's longer than the field moves left to keep the caret in view
  @test input.scroll == 0px
  type(" and a good deal more text than fits")
  view = text_view(input)
  @test input.scroll > 0px
  @test 0px <= width_to(input, input.cursor) - input.scroll <= view.width
  press(Keys.home)
  @test input.scroll == 0px

  # A click puts the caret under the mouse. A second click selects the word there.
  click(x) = (w.mouse = Vec2{px}(px(x), 20px); onkey(w, KeyPress{Keys.mouse_left}(0, w)); frame(w))
  click(view.left.value + width_to(input, 5).value + 1)
  @test (input.anchor, input.cursor) == (5, 5)
  click(view.left.value + width_to(input, 5).value + 1)
  @test (input.anchor, input.cursor) == (4, 9)      # "lines"

  # It keeps the keys it uses, and lets the others go on up
  @test emit(input, KeyPress{Keys.left}(0, w)) === handled
  @test emit(input, KeyPress{Keys.enter}(0, w)) === nothing
  @test emit(input, KeyPress{Keys.up}(0, w)) === nothing
end
