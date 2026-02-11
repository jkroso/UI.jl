# Context Menu
#
# Right-click anywhere to show a context menu at the cursor position.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui show_menu! hide_menu!
@use "../Interface/abstract" SemanticUI describe

@def mutable struct ContextExample <: SemanticUI end

describe(::ContextExample) =
  Box(width(grow=GrowType.Grow),
      height(grow=GrowType.Grow),
      Alignment.Center,
      background("white"),
    Box(height(20px),
      Text("Right-click anywhere for context menu", size=13pt, color=rgb(120,120,120))))

const example = ContextExample()
const window = Window(example, title="Context Menu", size=(350px, 250px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

const menu_items = ["Cut", "Copy", "Paste", "Select All"]

onkey(w::Window, ::KeyPress{Keys.mouse_right}) = begin
  show_menu!(w, menu_items, w.mouse[1], w.mouse[2], 150px,
             onselect=idx -> idx > 0 && println("Selected: ", menu_items[idx]))
end

display(window)
