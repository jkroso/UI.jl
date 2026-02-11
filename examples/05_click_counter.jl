# Counter Component
#
# A click counter rendered in a window. Click to increment.

@use "github.com/jkroso/MiniFB.jl/skia"...
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Descriptive"...
@use "../Interface/Specific"...
@use "../Interface/draw" draw ui
@use Colors: @colorant_str

const count = Ref(0)
const window = Window(title="Counter", size=(200px, 100px))
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)
onkey(w::Window, ::KeyPress{Keys.mouse_left}) = count[] += 1

ui(window) =
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
    Alignment.Center, background("white"),
    Box(width(grow=GrowType.Grow), height(40px),
      Text("Count: $(count[])", size=24pt, family="Helvetica")))
errormonitor(@async open(window))
