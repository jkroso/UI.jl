@use Test: @test, @test_throws
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "./abstract" SemanticUI describe integrate
@use "./Geometric"...
@use "./draw" frame
@use "./testing"...
@use "./Semantic/TextInput" TextInput
@use "./Semantic/Checkbox" Checkbox
@use "./Semantic/Dropdown" Dropdown
@use "./Semantic/Button" Button

# Fill in a form the way a user would, in a window that's never opened
@def mutable struct Form <: SemanticUI end
describe(f::Form) = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(10px), child_gap=8px, Alignment.Start,
                           background("white"), f.children...)

let name = TextInput(placeholder="Name"), agree = Checkbox(label="I agree"), size = Dropdown(options=["Small", "Large"]), sent = Ref(false)
  w = Window(Form(name, agree, size, Button("Send", onclick=_ -> sent[] = true)), size=(300px, 220px))
  frame(w)
  click!(w, name)
  type!(w, "Ada")
  click!(w, agree)
  click!(w, size); press!(w, Keys.down); press!(w, Keys.down); press!(w, Keys.enter)
  @test !sent[]
  click!(w, w.ui.children[4])
  @test integrate(name) == "Ada"
  @test integrate(agree)
  @test integrate(size) == "Large"
  @test sent[]
  press!(w, Keys.a, Keys.cmd); press!(w, Keys.backspace)     # the name field still has the keyboard
  @test integrate(name) == ""

  # A picture of the window, to look at or to compare with one that's kept
  picture = joinpath(mktempdir(), "form.png")
  save_png(picture, w)
  shot = pixels(picture)
  @test Base.size(shot) == (440, 600)                        # 220 × 300 at two pixels to the point
  @test difference(shot, shot) == 0
  @test difference(shot, fill(0xffffffff, 440, 600)) > 0.01
end

# A node that's scrolled out of view can't be clicked, and `click!` says so
@def mutable struct Long <: SemanticUI end
describe(l::Long) = Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Column(width(grow=GrowType.Grow), l.children...))
let boxes = [Checkbox(label="Box $i") for i in 1:20], w = Window(Long(boxes...), size=(200px, 100px))
  frame(w)
  click!(w, boxes[2])
  @test integrate(boxes[2])
  @test_throws ErrorException click!(w, boxes[15])
  @test !integrate(boxes[15])
end
