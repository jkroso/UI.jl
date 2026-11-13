# STL Viewer
#
# Shows the 3D model in an STL file. Drag the model to turn it. Hold ⌘ and
# scroll to make it bigger or smaller. Click it twice to put it back as it was.
#
#     julia --project=. examples/28_stl_viewer.jl ~/Desktop/part.stl
#
# Without a file it shows a knot.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use "../Interface/Semantic/STLViewer" STLViewer
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

@def mutable struct ViewerDemo <: SemanticUI end

describe(demo::ViewerDemo) =
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(20px), background(colorant"rgb(245,245,248)"),
    describe!(demo.firstchild))

const file = isempty(ARGS) ? joinpath(@__DIR__, "assets", "knot.stl") : expanduser(ARGS[1])
const example = ViewerDemo(STLViewer(file, height=420px))

display(Window(example, title="STL Viewer", size=(720px, 510px)))
