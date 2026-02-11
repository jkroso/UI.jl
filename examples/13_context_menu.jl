# Context Menu
#
# Right-click anywhere to show a context menu with icons at the cursor position.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui show_menu! hide_menu!
@use "../Interface/abstract" SemanticUI describe
@use "../Interface/Semantic/Menu" Item Menu onselect
@use "../Interface/Semantic/Icon" Icon

@def mutable struct ContextExample <: SemanticUI end

describe(::ContextExample) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      Alignment.Center,
      background("white"),
    Box(height(20px),
      Text("Right-click anywhere for context menu", size=13pt, color=rgb(120,120,120))))

const example = ContextExample()

const menu = Menu(
  Item(Icon("scissors"), "Cut"),
  Item(Icon("copy"), "Copy"),
  Item(Icon("clipboard"), "Paste"),
  Item(Icon("check2-all"), "Select All"))

onselect(::Menu, idx::Int) = idx > 0 && println("Selected: ", menu.children[idx].label)
onkey(w::Window, ::KeyPress{Keys.mouse_right}) = show_menu!(w, menu, w.mouse..., 160px)
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(Window(example, title="Context Menu", size=(350px, 250px), animating=true))
