@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "./abstract" SemanticUI describe
@use "./Geometric"...
@use "./Specific"...
@use "./draw" inside hittest

# The middle of this 400×300 box is (200, 150) and the biggest circle in it has a
# radius of 150, so a wedge's radii of 0.2 and 0.6 are 30px and 90px
const quarter = Wedge(width(400px), height(300px), inner=0.2, outer=0.6, start=0, sweep=90)
let wedge = describe(quarter, (400px, 300px))
  @test inside(wedge, (250px, 100px))      # up and to the right: in the slice
  @test !inside(wedge, (150px, 100px))     # up and to the left: outside its angles
  @test !inside(wedge, (210px, 140px))     # too near the middle
  @test !inside(wedge, (300px, 20px))      # too far out, though still in its box
end

# Its angles can wrap past 12 o'clock
const top = Wedge(width(400px), height(300px), outer=1.0, start=315, sweep=90)
let wedge = describe(top, (400px, 300px))
  @test inside(wedge, (180px, 50px)) && inside(wedge, (220px, 50px))
  @test !inside(wedge, (200px, 250px))
end

# Wedges stacked in one box each get the clicks on their own slice
@def mutable struct Slice <: SemanticUI
  start::Float64 = 0.0
end
describe(s::Slice) = Wedge(width(grow=GrowType.Grow), height(grow=GrowType.Grow), start=s.start, sweep=180)
const left, right = Slice(start=180), Slice(start=0)
const pie = Stack(width(200px), height(200px), right, left)
let scene = describe(pie, (200px, 200px))
  @test hittest(scene, (150px, 100px)) === right
  @test hittest(scene, (50px, 100px)) === left
end

# A shadow is drawn outside its box only. This box is see-through, at 30–70px each way,
# and its shadow is 10px lower, so only the 10px below the box are black
@use "./draw" draw
@use "github.com/jkroso/MiniFB.jl/skia" drawing
const lifted = Box(width(100px), height(100px), padding(30px), Box(width(40px), height(40px), shadow(0, 10, 0, "black")))
let pixels = drawing(draw, (100px, 100px), describe(lifted, (100px, 100px)), scale=(1f0, 1f0))
  drawn(x, y) = reinterpret(UInt32, pixels[y, x]) != 0
  @test drawn(50, 75)        # below the box
  @test !drawn(50, 50)       # inside the box
  @test !drawn(50, 85)       # past the end of the shadow
  @test !drawn(25, 75)       # left of it
end

# A blur takes the shadow further out, and `spread` further still
let soft = Box(width(100px), height(100px), padding(30px), Box(width(40px), height(40px), shadow(0, 0, 8, "black", spread=4px)))
  pixels = drawing(draw, (100px, 100px), describe(soft, (100px, 100px)), scale=(1f0, 1f0))
  shade(x, y) = reinterpret(UInt32, pixels[y, x]) >> 24
  @test shade(50, 72) > shade(50, 76) > 0
  @test shade(50, 50) == 0
end
