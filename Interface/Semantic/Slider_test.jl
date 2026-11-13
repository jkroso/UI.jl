@use Test: @test
@use "github.com/jkroso/Font.jl/units" px
@use "../abstract" GeometricUI
@use "../Geometric"...
@use "../Specific"...
@use "./Slider" Slider

layout(s) = describe(convert(GeometricUI, s), (300px, 24px))

# Without `format` the track is the whole slider
let ui = layout(Slider(value=5, min=0, max=10))
  @test length(ui.children) == 1
  @test ui.children[1].width == 300px
end

# With `format` the value shows as text on the right of the track
let ui = layout(Slider(value=5, min=0, max=100, format=v -> round(Int, v)))
  track, label = ui.children
  @test label.children[1].lines == ["5"]
  @test track.left + track.width < label.left
  @test label.left + label.width == 300px
  # The text has room for its widest value, so the track is as long for 5 as for 100
  @test track.width == layout(Slider(value=100, min=0, max=100, format=v -> round(Int, v))).children[1].width
end

# A click on the track moves the slider there. A click on the text beside it doesn't.
@use "github.com/jkroso/MiniFB.jl" Window KeyPress Keys onkey
@use "../draw" frame
@use GeometryBasics: Vec2
let s = Slider(value=5, min=0, max=10, format=v -> round(Int, v))
  w = Window(Box(width(300px), height(44px), padding(10px), s), size=(300px, 44px))
  frame(w)
  click(x) = (w.mouse = Vec2{px}(px(x), 22px); onkey(s, KeyPress{Keys.mouse_left}(0, w)))
  click(292)                     # on the number
  @test s.value == 5
  click(10 + s.cached_width.value / 4)
  @test s.value ≈ 2.5
end

# A slider with a `step` stops only at its detents, and tells `onchange` only when it moves to another one
let changes = Ref(0), s = Slider(value=13, min=11, max=40, step=1, onchange=_ -> changes[] += 1)
  w = Window(Box(width(310px), height(44px), padding(10px), s), size=(310px, 44px))
  frame(w)
  click(x) = (w.mouse = Vec2{px}(px(x), 22px); onkey(s, KeyPress{Keys.mouse_left}(0, w)))
  click(10 + 290 * 4.4 / 29)     # between 15 and 16, nearer to 15
  @test s.value == 15
  @test changes[] == 1
  click(10 + 290 * 4.6 / 29)     # nearer to 16
  @test s.value == 16
  click(10 + 290 * 4.7 / 29)     # 16 again
  @test changes[] == 2
  onkey(s, KeyPress{Keys.right}(0, w))
  @test s.value == 17
  onkey(s, KeyPress{Keys.left}(0, w)); onkey(s, KeyPress{Keys.left}(0, w))
  @test s.value == 15
  s.value = 40.0
  onkey(s, KeyPress{Keys.right}(0, w))
  @test s.value == 40
  @test changes[] == 5
end
