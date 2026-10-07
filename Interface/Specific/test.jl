@use Test: @test
@use "github.com/jkroso/Prospects.jl" @field_str
@use "../Geometric"...
@use "."... grow!
@use "../abstract" WrapMode

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


@test field"width".(describe(growexample, (600px, 10px)).children) == px[100,200,200,100]
@test field"width".(describe(growmaxed, (600px, 10px)).children) == px[100,250,150,100]
@test field"width".(describe(shrinkexample, (600px, 10px)).children) == px[350,75,100,75]
@test field"width".(describe(textwrap_example, (600px, 10px)).children) == px[150, 250]
@test describe(textwrap_example, (600px, 10px)).children[2].lines[1] == "Wibz UIflibber jabberz devz n’"

# Test vertical grow behavior — distribute extra height equally among growable children
const grow_vertical_example = Box(width(400px), height(600px),
                                   Box(width(100px), height(preferred=100px, grow=GrowType.Grow)),
                                   Box(width(100px), height(preferred=200px, grow=GrowType.Grow)),
                                   Box(width(100px), height(150px)))
@test field"height".(describe(grow_vertical_example, (400px, 600px)).children) == px[225,225,150]

# Test vertical shrink behavior — shrink largest children to fit
const shrink_vertical_example = Box(width(400px), height(400px),
                                     Box(width(100px), height(200px)),
                                     Box(width(100px), height(preferred=200px, grow=GrowType.Grow)),
                                     Box(width(100px), height(100px)))
@test field"height".(describe(shrink_vertical_example, (400px, 400px)).children) == px[150,150,100]

const fullscreen = Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow))
@test describe(fullscreen, (100px, 100px)).width == 100px
@test describe(fullscreen, (100px, 100px)).height == 100px

# A Column measures its height after its text has wrapped
const wrapped_column = Column(width(300px), child_gap=8px,
                              Text("A paragraph long enough to wrap onto several lines inside three hundred pixels"),
                              Box(width(50px), height(20px)))
let col = describe(wrapped_column, (800px, 600px))
  text, box = col.children
  @test length(text.lines) > 1
  @test box.top ≈ text.top + text.height + 8px
  @test col.height ≈ text.height + 8px + 20px
end

# Percentages share what's left after padding and gaps, like Clay's SIZING_PERCENT
const percent_row = Row(width(1000px), padding(32px), child_gap=32px,
                        Box(width(percent=0.55)), Box(width(percent=0.45)))
@test all(isapprox.(field"width".(describe(percent_row, (1000px, 100px)).children), px[497.2, 406.8]))

# justify places children along the layout direction
const centred = Column(width(400px), height(300px), justify=Alignment.Center, Box(width(10px), height(100px)))
@test describe(centred, (400px, 300px)).children[1].top == 100px
const ended = Row(width(400px), height(50px), justify=Alignment.End, Box(width(100px), height(10px)))
@test describe(ended, (400px, 50px)).children[1].left == 300px

# Growing elements start at their content size, so a spacer doesn't squeeze its neighbours
const header = Row(width(300px), child_gap=10px,
                   Box(width(80px)), Box(width(grow=GrowType.Grow)), Box(padding(10px), Text("Github", wrap=WrapMode.none)))
let row = describe(header, (300px, 50px))
  button = row.children[3]
  @test button.width ≈ button.children[1].width + 20px
  @test sum(field"width", row.children) + 20px ≈ 300px
end

# A container can't shrink below text that doesn't wrap...
const tight = Row(width(60px), Box(Text("unbreakable", wrap=WrapMode.none)))
@test describe(tight, (60px, 50px)).children[1].width > 60px
# ...unless it clips its content
const clipped = Row(width(60px), Box(clip=true, Text("unbreakable", wrap=WrapMode.none)))
@test describe(clipped, (60px, 50px)).children[1].width == 60px

# Text doesn't absorb spare height; it's exactly as tall as its lines
const tall = Column(width(200px), height(400px), Text("one line"))
@test describe(tall, (200px, 400px)).children[1].height < 50px

# A Wedge places its child like a Box does, in the middle of its box
const pie = Wedge(width(200px), height(100px), outer=0.5, Box(width(20px), height(10px)))
let wedge = describe(pie, (200px, 100px))
  @test (wedge.children[1].left, wedge.children[1].top) == (90px, 45px)
end
