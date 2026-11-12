# A Markdown editor made with UI.jl

This page is a Markdown file. Each line is drawn the way it will read, and the
markup characters stay out of sight. **Click a line** and its markup shows again,
so you can change it. Press ⌘S to write your changes to the file.

## Text

You can write in **bold**, in *italic* or in ***both***. Use backticks for
`code`, and square brackets for [a link](https://github.com/jkroso/UI.jl). Hold
⌘ and click a link to open it. A name like snake_case_name keeps its underscores.

> A line that starts with > is a quote.
> It can run over several lines.

## Lists

1. Press Return at the end of this line. The next number is typed for you.
2. Press Return on an empty item to end the list.
3. Press Tab to move an item in, and shift-Tab to move it back out.

- A long item wraps onto the next line, and the text of that line starts under the text of the first line, not under the bullet.
  - Items can sit inside other items.
- Select some words and press ⌘B or ⌘I.

## Tables

| Keys | What they do |
|------|--------------|
| ⌘P | Finds a file in this folder by name |
| ⌘\ | Shows and hides the list of files |
| ⌘Z and ⌘⇧Z | Undo and redo |
| ⌥← and ⌥→ | Move the caret a word at a time |
| ⌘+ and ⌘- | Make the text bigger and smaller. ⌘0 puts it back to the size it started at. |

Click a cell and type. Tab goes to the next cell and Return goes down a row.
Both add a row when they reach the end of the table.

## Code

```julia
# Only the lines on screen are built
describe(d::Document) = begin
  e = editor(d)
  title = "Lines $(first(e.shown)) to $(last(e.shown))"
  Column(fixed(e.width), spacer(28px), map(describe, e.layout[e.shown])...)
end
```

The line that opens a code block names its language, and the code is coloured to
match. Try changing `julia` to `python`.

## Live blocks

A code block in the language `ui` holds Julia code. The page runs the code and
shows what it makes: a node from any Julia module, or any other value as text.

```ui
@use "./widgets.jl" Counter
Counter()
```

```ui
@use "./widgets.jl" Meter
Meter(done=0.7)
```

A file path shows as a breadcrumb. Click its last name to list what's in the
folder, and click a file in the list to make it the path.

```ui
@use "github.com/jkroso/URI.jl/FSPath" @fs_str
fs"."
```

To change the code, move the caret into the block with ↑ or ↓, or hold ⌥ and
click the block.

The page [components.md](components.md) has a live block for each of UI.jl's
components: checkboxes, switches, a slider, a menu, a colour picker, a text
field, a tree and an inspector. It shows shadows too. Hold ⌘ and click the link to open it.

## Sheets

A code block in the language `sheet` works things out. Each row has a name and
a Julia expression. An expression can use the names of the rows above it, and
numbers can have units.

```sheet
Wall length = 12m
Wall height = 2.4m
Area = wall length * wall height
Coats = 2
Coverage = 16m^2 / litre
Litres = area * coats / coverage
Tins = ceil(litres / 4litre)
```

Click a cell and type. Tab goes to the next cell and Return starts a row. To see
the sheet as lines of code, hold ⌥ and click it.

---

The buttons at the top right list the headings, change the font and change the
colours.
