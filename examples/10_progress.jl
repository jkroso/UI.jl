# Progress Bar
#
# An animated progress bar that fills over time.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/ProgressBar"...

@def mutable struct ProgressExample <: SemanticUI end

const start_time = Ref(time())

describe((;firstchild)::ProgressExample) = begin
  elapsed = time() - start_time[]
  firstchild.value = mod(elapsed / 4.0, 1.0)
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      padding(20px),
      Alignment.Center,
      background("white"),
    Column(width(grow=GrowType.Grow), padding(10px),
      Box(width(grow=GrowType.Grow), height(20px),
        Text("$(round(Int, firstchild.value * 100))%", size=14pt)),
      Box(width(4px), height(8px)),
      describe!(firstchild)))
end

const example = ProgressExample(ProgressBar(value=0.0))

const window = Window(example, title="Progress Bar", size=(350px, 110px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
