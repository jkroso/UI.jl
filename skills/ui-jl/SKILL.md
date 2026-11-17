---
name: ui-jl
description: Write, change and test apps made with UI.jl, the Julia UI library at github.com/jkroso/UI.jl (SemanticUI nodes, describe, Row/Column/Box layout, MiniFB windows). Covers how a component is written, the layout rules and their traps, testing a window without opening it, and hot reload. Use when code loads github.com/jkroso/UI.jl, as Kaydown and UI.jl's own examples do, or when the user mentions UI.jl, describe, SemanticUI, a window test or hot reload.
---

# UI.jl

UI.jl turns data into pixels in steps. `describe(data)` makes semantic nodes, `describe(node)` makes geometry, and the window lays the geometry out and draws it. Input goes back up to the semantic nodes, and `integrate(node)` reads the data out again.

`Readme.md` at the top of the repo is the reference for the API. Read it before you write a component. This skill holds what the Readme doesn't: the idioms, the traps and the workflow. When a detail matters, read the source. Each file starts with a comment that says what it does.

- `Interface/abstract.jl`: nodes, themes, `describe`, `inputs`, `reuse!`.
- `Interface/Geometric/main.jl`: `Row`, `Column`, `Box`, `Stack`, `Scroll`, `Text`, `Image` and the style helpers.
- `Interface/draw.jl`: the frame, events, `rect`, `popup!`, menus, tooltips, `redraw_in!`.
- `Interface/Semantic/`: the ready-made components, one file each, with a `_test.jl` beside most.
- `Interface/testing.jl`: helpers that click and type in a window that isn't on the screen.
- `examples/`: `05_click_counter.jl` is the smallest app. `22_todo_list.jl` shows the whole pipeline. `26_finder.jl` is a full app.

## A component

```julia
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...                      # Window, Keys, KeyPress, MouseMove, Typed, onkey, onmouse, ontype
@use "github.com/jkroso/UI.jl/Interface/Geometric"...       # Row, Column, Box, Text, width, height, padding, px ...
@use "github.com/jkroso/UI.jl/Interface/abstract" SemanticUI describe handled inputs
@use "github.com/jkroso/UI.jl/Interface/draw" ishovered cursor

"A row that you click to choose it"
@def mutable struct Choice <: SemanticUI
  label::String = ""
  chosen::Bool = false
end

describe(c::Choice) =
  Row(width(grow=GrowType.Grow), height(28px), padding(10px, 0px), radius(6px), Alignment.Start,
      background(c.chosen ? "lightblue" : ishovered(c) ? "whitesmoke" : "white"),
    Text(c.label, size=13px))

inputs(c::Choice) = (c.label, c.chosen)        # optional: what describe reads, so the geometry is used again
cursor(::Choice) = :hand
onkey(c::Choice, ::KeyPress{Keys.mouse_left}) = (c.chosen = !c.chosen; handled)
```

- `@def` gives every field a default and a keyword constructor. A node also has `parent`, `children`, `firstchild`.
- State lives in the semantic node. Geometry is made new on each frame, so never keep a `Row` to change later.
- A handler that returns `handled` stops the event. Without it the event goes on to the nodes above.
- `onkey` gets mouse buttons and keys. `ontype` gets the characters that were typed. Use `ontype` for text.
- A node that must be the same object on each frame has to be kept: as a child (`add_child!`), in a field, or in a table that the app owns. Kaydown keeps them in `e.nodes` with its own `node!(make, e, key)`.
- Colours come from `theme(node)` in a reusable component, so it suits light and dark pages.
- Tab and ⇧Tab move the keyboard between the nodes that say `tabstop(::T) = true`, as `TextInput` does. An app whose top node sees every key must leave Tab unhandled for that to work, or return `handled` to keep Tab in one field.

## Workflow

1. Find the nearest thing that exists: a component in `Interface/Semantic`, or code in the app that draws something like it. Copy its shape.
2. Write the struct, `describe`, and the handlers.
3. Test it in a window that isn't on the screen, and save a picture. See [TESTING.md](TESTING.md). Look at the picture: a layout fault often shows only there.
4. Check each item of [TRAPS.md](TRAPS.md) that your layout touches. Most first drafts hit the first three.
5. For work by eye, run the app with hot reload:
   `julia --project=. <UI.jl>/examples/hot_reload.jl app.jl args`. The file must open its window in an `if abspath(PROGRAM_FILE) == @__FILE__` block. A saved change shows in the open window. A changed struct makes the window open again.

## Rules that hold everywhere

- Give lengths units: `12px`, `14pt`. `num`-like helpers that strip units belong to the app, not to UI.jl.
- `width(...)`/`height(...)` take one rule: nothing fits the content, a length fixes it, `grow=GrowType.Grow` shares spare room, `percent=0.5` takes a share of the parent.
- A window draws only when something asks. Call `redraw_in!(node, seconds)` from `describe` for an animation, a timer or a background job.
- Julia tasks run only while the window's loop yields. Work that must go on between frames gets its turn from a `describe` that calls `yield()`, and asks for the next frame with `redraw_in!`. Never block in a handler or a `describe`: a slow call there freezes the window.
- A changed `describe` that doesn't show means an `inputs` method leaves out a value. `skipping[] = false` turns the reuse off, to check.
- UI.jl is loaded by its GitHub path. `Kip.link("/path/to/UI.jl")` makes that path mean a folder on this Mac, so an app picks up your changes to UI.jl.
