# Flex Layout
#
# Containers support flexible sizing with grow and shrink behavior.
# Each dimension (Width/Height) has min, max, preferred, and a GrowType:
#   - GrowType.FitContent: default, sizes to content
#   - GrowType.Grow:       expands to fill available space
#   - GrowType.None:       fixed size, won't shrink

@use "github.com/jkroso/Prospects.jl" @field_str
@use "../Interface/Descriptive"...
@use "../Interface/Specific"...
@use Colors: @colorant_str

# Growing: items with Grow expand to fill remaining space
grow_example = Row(width(600px), background("darkblue"),
  Row(width(100px), height(100px), background("red")),
  Row(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
  Row(width(grow=GrowType.Grow), height(100px), background("lightgreen")),
  Row(width(100px), height(100px), background("lightblue")))

result = resolve(grow_example, (600px, 100px))
println("Grow example widths: ", field"width".(result.children))
# Fixed items keep their size, growable items split the remaining 400px
# => [100px, 200px, 200px, 100px]

# Growing with max constraint
grow_maxed = Row(width(600px), background("darkblue"),
  Row(width(100px), height(100px), background("red")),
  Row(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
  Row(width(grow=GrowType.Grow, max=150px), height(100px), background("lightgreen")),
  Row(width(100px), height(100px), background("lightblue")))

result = resolve(grow_maxed, (600px, 100px))
println("Grow maxed widths: ", field"width".(result.children))
# Second growable item capped at 150px, first gets the extra
# => [100px, 250px, 150px, 100px]

# Shrinking: when children exceed parent width, shrinkable items compress
shrink_example = Row(width(600px), background("darkblue"),
  Row(width(min=350px, preferred=350px), height(100px), background("red")),
  Row(width(min=50px, grow=GrowType.Grow, preferred=100px), height(100px), background("yellow")),
  Row(width(min=100px, grow=GrowType.Grow), height(100px), background("lightgreen")),
  Row(width(100px), height(100px), background("lightblue")))

result = resolve(shrink_example, (600px, 100px))
println("Shrink example widths: ", field"width".(result.children))
# => [350px, 75px, 100px, 75px]

# Fullscreen: grow to fill entire viewport
fullscreen = Row(width(grow=GrowType.Grow), height(grow=GrowType.Grow))
result = resolve(fullscreen, (1920px, 1080px))
println("Fullscreen: $(result.width) x $(result.height)")
# => 1920px x 1080px

# Alignment within containers
centered_box = Box(width(400px), height(200px),
  Alignment.Center,
  background("darkblue"),
  Row(width(100px), height(50px), background("white")))

result = resolve(centered_box, (400px, 200px))
child = result.children[1]
println("Centered child at: left=$(child.left), top=$(child.top)")

# Compose display versions into a scene
# Expected result: four sections stacked vertically showing
#   1. Grow: red | yellow (wide) | green (wide) | blue - growable items expand equally
#   2. Grow maxed: same but green is capped, yellow gets extra
#   3. Shrink: wide red | narrow yellow | green | narrow blue - items compressed to fit
#   4. Centered: small white box centered in a dark blue rectangle
scene = Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), background(colorant"rgb(240,240,240)"),
  Column(width(360px), height(grow=GrowType.Grow), padding(10px),
    Row(width(350px), height(40px), background("darkblue"),
      Row(width(50px), height(30px), background("red")),
      Row(width(min=75px, grow=GrowType.Grow), height(30px), background("yellow")),
      Row(width(grow=GrowType.Grow), height(30px), background("lightgreen")),
      Row(width(50px), height(30px), background("lightblue"))),
    Row(width(350px), height(40px), background("darkblue"),
      Row(width(50px), height(30px), background("red")),
      Row(width(min=75px, grow=GrowType.Grow), height(30px), background("yellow")),
      Row(width(grow=GrowType.Grow, max=75px), height(30px), background("lightgreen")),
      Row(width(50px), height(30px), background("lightblue"))),
    Row(width(350px), height(40px), background("darkblue"),
      Row(width(min=175px, preferred=175px), height(30px), background("red")),
      Row(width(min=25px, grow=GrowType.Grow, preferred=50px), height(30px), background("yellow")),
      Row(width(min=50px, grow=GrowType.Grow), height(30px), background("lightgreen")),
      Row(width(50px), height(30px), background("lightblue"))),
    Box(width(350px), height(80px), Alignment.Center, background("darkblue"),
      Row(width(60px), height(30px), background("white")))))

@use "../Interface/save" save_scene
save_scene(@__DIR__()*"/03_flex_layout.png", scene, (380px, 260px))
