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

---

The buttons at the top right list the headings, change the font and change the
colours.
