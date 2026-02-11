@use "github.com/jkroso/Rutherford.jl/test.jl" @test testset
@use "github.com/jkroso/Prospects.jl" @field_str
@use "../Descriptive"...
@use "."... grow!

const growexample = Box(width(600px), background("darkblue"),
                      Box(width(100px), height(100px), background("red")),
                      Box(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
                      Box(width(grow=GrowType.Grow), height(100px), background("yellow")),
                      Box(width(100px), height(100px), background("lightblue")))

const growmaxed = Box(width(600px), background("darkblue"),
                    Box(width(100px), height(100px), background("red")),
                    Box(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
                    Box(width(grow=GrowType.Grow, max=150px), height(100px), background("yellow")),
                    Box(width(100px), height(100px), background("lightblue")))

const shrinkexample = Box(width(600px), background("darkblue"),
                        Box(width(min=350px,preferred=350px), height(100px), background("red")),
                        Box(width(min=50px, grow=GrowType.Grow, preferred=100px), height(100px), background("yellow")),
                        Box(width(min=100px, grow=GrowType.Grow), height(100px), background("yellow")),
                        Box(width(100px), height(100px), background("lightblue")))

const textwrap_example = Box(width(400px), background("darkblue"),
                           Box(width(min=100px, preferred=150px), height(100px), background("red")),
                           Text("Wibz UIflibber jabberz devz n’ zany toolz setz to flibber flabber snazzy, zippy facez widda wacko eazy twisty"))


@test field"width".(resolve(growexample, (600px, 10px)).children) == px[100,200,200,100]
@test field"width".(resolve(growmaxed, (600px, 10px)).children) == px[100,250,150,100]
@test field"width".(resolve(shrinkexample, (600px, 10px)).children) == px[350,75,100,75]
@test field"width".(resolve(textwrap_example, (600px, 10px)).children) == px[150, 250]
@test resolve(textwrap_example, (600px, 10px)).children[2].lines[1] == "Wibz UIflibber jabberz devz n’"

# Test vertical grow behavior — distribute extra height equally among growable children
const grow_vertical_example = Box(width(400px), height(600px),
                                   Box(width(100px), height(preferred=100px, grow=GrowType.Grow)),
                                   Box(width(100px), height(preferred=200px, grow=GrowType.Grow)),
                                   Box(width(100px), height(150px)))
@test field"height".(resolve(grow_vertical_example, (400px, 600px)).children) == px[225,225,150]

# Test vertical shrink behavior — shrink largest children to fit
const shrink_vertical_example = Box(width(400px), height(400px),
                                     Box(width(100px), height(200px)),
                                     Box(width(100px), height(preferred=200px, grow=GrowType.Grow)),
                                     Box(width(100px), height(100px)))
@test field"height".(resolve(shrink_vertical_example, (400px, 400px)).children) == px[150,150,100]

const fullscreen = Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow))
@test resolve(fullscreen, (100px, 100px)).width == 100px
@test resolve(fullscreen, (100px, 100px)).height == 100px
