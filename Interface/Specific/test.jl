@use "github.com/jkroso/Rutherford.jl/test.jl" @test testset
@use "github.com/jkroso/Prospects.jl" @field_str
@use "../Descriptive"...
@use "."...

const growexample = Rect(width(600px), background("darkblue"),
                      Rect(width(100px), height(100px), background("red")),
                      Rect(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
                      Rect(width(grow=GrowType.Grow), height(100px), background("yellow")),
                      Rect(width(100px), height(100px), background("lightblue")))

const growmaxed = Rect(width(600px), background("darkblue"),
                    Rect(width(100px), height(100px), background("red")),
                    Rect(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
                    Rect(width(grow=GrowType.Grow, max=150px), height(100px), background("yellow")),
                    Rect(width(100px), height(100px), background("lightblue")))

const shrinkexample = Rect(width(600px), background("darkblue"),
                        Rect(width(min=350px,preferred=350px), height(100px), background("red")),
                        Rect(width(min=50px, grow=GrowType.Grow, preferred=100px), height(100px), background("yellow")),
                        Rect(width(min=100px, grow=GrowType.Grow), height(100px), background("yellow")),
                        Rect(width(100px), height(100px), background("lightblue")))

const textwrap_example = Rect(width(400px), background("darkblue"),
                           Rect(width(min=100px, preferred=150px), height(100px), background("red")),
                           Text("Wibz UIflibber jabberz devz n’ zany toolz setz to flibber flabber snazzy, zippy facez widda wacko eazy twisty"))


@test field"width".(resolve(growexample, (600px, 10px)).children) == px[100,200,200,100]
@test field"width".(resolve(growmaxed, (600px, 10px)).children) == px[100,250,150,100]
@test field"width".(resolve(shrinkexample, (600px, 10px)).children) == px[350,75,100,75]
@test field"width".(resolve(textwrap_example, (600px, 10px)).children) == px[150, 250]
@test resolve(textwrap_example, (600px, 10px)).children[2].lines[1] == "Wibz UIflibber jabberz devz n’"

# Test vertical grow behavior
const grow_vertical_example = Rect(width(400px), height(600px),
                                   Rect(width(100px), height(100px), grow(height=GrowType.Grow)),
                                   Rect(width(100px), height(200px), grow(height=GrowType.Grow)),
                                   Rect(width(100px), height(150px)))

# Test vertical shrink behavior
const shrink_vertical_example = Rect(width(400px), height(400px),
                                     Rect(width(100px), height(200px)),
                                     Rect(width(100px), height(300px), grow(height=GrowType.Grow)),
                                     Rect(width(100px), height(150px)))

# Test vertical grow - should distribute extra height (600px - 450px = 150px) to growing children
@test field"height".(resolve(grow_vertical_example, (400px, 600px)).children) == px[200,300,150]

# Test vertical shrink - should shrink growing child to fit in 400px total height
@test field"height".(resolve(shrink_vertical_example, (400px, 400px)).children) == px[200,250,150]

const fullscreen = Rect(width(grow=GrowType.Grow), height(grow=GrowType.Grow))
@test resolve(fullscreen, (100px, 100px)).width == 100px
@test resolve(fullscreen, (100px, 100px)).height == 100px
