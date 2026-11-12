# Components

Each block on this page is a `ui` code block. Its code makes one of the
components in `Interface/Semantic`, and the page shows it. Try them: each one
keeps what you do to it until its code changes.

To see the code of a block, hold ⌥ and click the block. A block can make a
layout too, like a `Column` with components in it.

## Checkboxes and switches

```ui
@use "../../Interface/Semantic" Checkbox
@use "../../Interface/Geometric" Column
Column(Checkbox(label="Check the spelling", checked=true),
       Checkbox(label="Use smart quotes"),
       Checkbox(label="Show the word count", checked=true))
```

```ui
@use "../../Interface/Semantic" Toggle
@use "../../Interface/Geometric" Column Row Text Alignment px
switch(name, on) = Row(child_gap=12px, Toggle(on=on), Text(name, size=17px))
Column(Alignment.Start, child_gap=8px, switch("Wi-Fi", true), switch("Bluetooth", false))
```

## Choices

```ui
@use "../../Interface/Semantic" RadioGroup
RadioGroup(labels=["Sepia", "Paper", "Night"], selected=1)
```

Click the box to open its menu.

```ui
@use "../../Interface/Semantic" Dropdown
@use "../../Interface/Geometric" Box width px
Box(width(240px), Dropdown(options=["Charter", "Helvetica Neue", "Menlo", "Lucida Grande"]))
```

## Numbers and colours

Drag the slider, or click it and press ← and →.

```ui
@use "../../Interface/Semantic" Slider
Slider(value=0.3)
```

```ui
@use "../../Interface/Semantic" ColorPicker
ColorPicker()
```

## Text

Click the box and type. Press Escape to go back to the page.

```ui
@use "../../Interface/Semantic" TextInput
@use "../../Interface/Geometric" Box width px
Box(width(320px), TextInput(placeholder="Type your name"))
```

```ui
@use "../../Interface/Semantic" KeyCombo
@use "../../Interface/Geometric" Row px
Row(child_gap=24px, KeyCombo(:S, :cmd), KeyCombo(:Z, :cmd, :shift), KeyCombo(:P, :cmd), KeyCombo(:ArrowUp, :opt))
```

Move the mouse over the box to see its tooltip.

```ui
@use "../../Interface/Semantic" Tooltip
Tooltip("Move the mouse here", "A tooltip can hold any node", placement=:right)
```

## Trees

Click a name with an arrow to open it. Use the arrow keys to move through
the tree.

```ui
@use "../../Interface/Semantic/ListTree" ListTree ItemGroup Item
@use "../../Interface/Geometric" Box width px
Box(width(320px), ListTree(
  ItemGroup("examples",
    ItemGroup("markdown_editor",
      Item("components.md"),
      Item("welcome.md"),
      Item("widgets.jl")),
    Item("26_finder.jl"),
    Item("28_markdown_editor.jl")),
  ItemGroup("Interface",
    ItemGroup("Semantic",
      Item("Checkbox.jl"),
      Item("Slider.jl")),
    Item("draw.jl"))))
```

The inspector shows what's in a Julia value. Click a value to change it.

```ui
@use "../../Interface/Semantic" Inspector inspect
@use "../../Interface/Geometric" Box width px
settings = Dict{String,Any}("font" => "Charter", "size" => 17, "spelling" => true,
                            "recent" => ["welcome.md", "components.md"])
Box(width(420px), Inspector(inspect(settings, label="settings")))
```
