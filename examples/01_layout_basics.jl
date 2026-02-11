# Layout Basics
#
# The Geometric layer provides three container types for layout:
#   - Row:    children arranged horizontally
#   - Column: children arranged vertically
#   - Box:    a single-child container
#
# The describe() function converts these into ConcreteUI with absolute positions.

@use "github.com/jkroso/Prospects.jl" @field_str
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use Colors: @colorant_str

# A simple row with three colored boxes
simple_row = Row(width(400px), height(80px), background("darkblue"),
Row(width(100px), height(60px), background("red")),
Row(width(100px), height(60px), background("yellow")),
Row(width(100px), height(60px), background("lightblue")))

result = describe(simple_row, (400px, 80px))
@assert field"width".(result.children) == px[100, 100, 100]
@assert field"height".(result.children) == px[60, 60, 60]
@assert length(result.children) == 3

# A column stacking items vertically
simple_column = Column(width(200px), height(240px), background("darkblue"), padding(10px, 0px),
Row(width(180px), height(80px), background("coral")),
Row(width(180px), height(80px), background("gold")),
Row(width(180px), height(80px), background("mediumseagreen")))

result = describe(simple_column, (200px, 300px))
@assert field"height".(result.children) == px[80, 80, 80]
@assert field"width".(result.children) == px[180, 180, 180]
# children stack vertically: each top = previous top + previous height
@assert result.children[1].top < result.children[2].top < result.children[3].top

# Nested layout: a column containing rows
nested = Column(width(400px), height(300px), background("white"),
Row(width(380px), height(50px), background("steelblue"),
Row(width(100px), height(40px), background("lightyellow")),
Row(width(100px), height(40px), background("lightcoral"))),
Row(width(380px), height(50px), background("darkseagreen"),
Row(width(150px), height(40px), background("lightyellow")),
Row(width(150px), height(40px), background("lightcoral"))))

result = describe(nested, (400px, 300px))
@assert result.width == 400px
@assert result.height == 300px
# outer column has two rows
@assert length(result.children) == 2
# each row has two children
@assert length(result.children[1].children) == 2
@assert length(result.children[2].children) == 2
# rows are stacked vertically
@assert result.children[2].top == result.children[1].top + result.children[1].height
# children within a row share the same top offset
@assert result.children[1].children[1].top == result.children[1].children[2].top
# children within a row are laid out left to right
@assert result.children[2].children[1].left < result.children[2].children[2].left

# Compose display versions into a single scene
# Expected result: three sections stacked vertically on a light gray background
#
#   1. Row: a dark blue bar with three small boxes (red, yellow, light blue)
#      side by side, vertically centered
#
#   2. Column: a dark blue rectangle with three horizontal bands
#      (coral, gold, green) stacked top to bottom
#
#   3. Nested: a white box with a thin gray border containing two rows stacked
#      vertically. The top row is steel blue with two small boxes (cream, pink)
#      side by side. The bottom row is dark sea green with the same.
display_row = Row(width(240px), height(50px), background("darkblue"),
Row(width(80px), height(40px), background("red")),
Row(width(80px), height(40px), background("yellow")),
Row(width(80px), height(40px), background("lightblue")))

display_column = Column(width(200px), height(120px), background("darkblue"),
Row(width(180px), height(40px), background("coral")),
Row(width(180px), height(40px), background("gold")),
Row(width(180px), height(40px), background("mediumseagreen")))

display_nested = Column(width(300px), height(120px), background("white"), border(1px, :solid, colorant"rgb(200,200,200)"), padding(0px, 10px),
Row(width(280px), height(50px), background("steelblue"), padding(10px, 0px),
Row(width(100px), height(40px), background("lightyellow")),
Row(width(100px), height(40px), background("lightcoral"))),
Row(width(280px), height(50px), background("darkseagreen"), padding(10px, 0px),
Row(width(130px), height(40px), background("lightyellow")),
Row(width(130px), height(40px), background("lightcoral"))))

scene = Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), background(colorant"rgb(240,240,240)"),
Column(width(320px), height(grow=GrowType.Grow), padding(10px),
display_row,
display_column,
display_nested))

# --- Save as image ---
@use "../Interface/save" save_scene
save_scene(@__DIR__()*"/01_layout_basics.png", scene, (320px, 340px))
