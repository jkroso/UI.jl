# List Tree
#
# A collapsible tree view with keyboard navigation and tree connector lines.
# Use arrow keys: Up/Down to navigate, Right to expand, Left to collapse.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe! focus
@use "../Interface/Semantic/ListTree" ListTree ItemGroup Item
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

@def mutable struct TreeDemo <: SemanticUI end

describe(demo::TreeDemo) =
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(20px), Alignment.Start, background(colorant"rgb(245,245,248)"),
    Column(width(300px), Alignment.Start,
      Box(height(24px), Text("Motorsport Categories", size=14pt, weight=700, color=colorant"rgb(30,30,30)")),
      Box(height(8px)),
      describe!(demo.firstchild)))

const tree = ListTree(
  ItemGroup("Openwheel",
    ItemGroup("Formula 1",
      ItemGroup("Formula 2",
        Item("Formula 3"),
        Item("Formula Renault"),
        Item("Formula Ford"))),
    ItemGroup("Indycar",
      Item("Cart"))),
  ItemGroup("Stockcar",
    ItemGroup("Nascar",
      Item("Xfinity"),
      Item("Trucks")),
    ItemGroup("Supercars",
      ItemGroup("Super 2",
        Item("Super 3")))))

const example = TreeDemo(tree)
const window = Window(example, title="List Tree", size=(400px, 500px), animating=true)
focus(tree)

display(window)
