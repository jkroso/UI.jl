@use "github.com/jkroso/Prospects.jl" @def @property
@use "github.com/jkroso/MiniFB.jl/skia" SkiaFont rectangle line font_metrics
@use "github.com/jkroso/MiniFB.jl" Window Keys KeyPress MouseMove Typed onkey onmouse ontype int
@use "github.com/jkroso/Font.jl" Font ["units" pt px]
@use "github.com/jkroso/Units.jl" Length
@use "../Geometric"...
@use "../Specific"... text_width font
@use "../abstract" SemanticUI WrapMode describe integrate window_of focus theme scale handled sized
@use "../draw" draw cursor rect clipboard clipboard! with_clip redraw_in!
@use "../fonts" skia_font
@use Colors: @colorant_str, Colorant, RGBA
@use GeometryBasics: Vec2

"""
A field for one line of text. It takes the characters the keyboard types, so it
works with any keyboard layout. Left, Right, Home and End move the caret, and
Shift selects with them. Option moves a word at a time, and Cmd goes to an end
of the line. Cmd-A selects everything, and Cmd-C, Cmd-X and Cmd-V copy, cut and
paste. A double click selects a word. Text that's longer than the field moves
sideways to keep the caret in view.

`integrate(input)` is the text that's in it.
"""
@def mutable struct TextInput <: SemanticUI
  text::String = ""
  cursor::Int = 0         # 0-based: 0=before first char, n=after nth char
  anchor::Int = 0         # selection anchor; equals cursor when no selection
  last_action::Float64 = time()
  # config
  font_family::Union{String,Nothing} = nothing   # `nothing` uses the theme's family, like the labels around it
  font_size::Length = 14pt   # in points, or in pixels to be the same number of pixels on every screen
  placeholder::String = "Type here..."
  color::Union{Colorant,Nothing} = nothing               # the typed text and the caret. `nothing` uses the theme's text
  placeholder_color::Union{Colorant,Nothing} = nothing   # `nothing` uses the theme's dim
  # `look(input, text)` returns the geometry around `text`, which shows what's
  # typed. Leave it as `nothing` for the standard bordered box.
  look::Any = nothing
  scroll::px = 0px            # how far the text has moved left, to keep the caret in view
  last_click::Float64 = 0.0   # when it was last clicked, to tell a double click
  picked_word::Bool = false   # the last click was a double click, which selected a word
end

"The colour of the typed text and the caret"
ink(input::TextInput) = something(input.color, theme(input).text)

"The size its text is drawn at: `font_size` when the theme's text has its usual size, and bigger or smaller with the theme"
text_size(input::TextInput) = sized(input.font_size, theme(input))

"The font family of its text"
family(input::TextInput) = something(input.font_family, theme(input).family)

"The Skia font that measures and draws its text"
font(input::TextInput) = skia_font(family(input), text_size(input))

"How wide the first `n` characters of its text are"
width_to(input::TextInput, n::Int) = n == 0 ? 0px : text_width(font(input), first(input.text, n))

"""
The typed text, or the placeholder in grey when nothing has been typed. It's in
a box that cuts it off at the left and right, and it moves left by `scroll`.
"""
content(input::TextInput) = begin
  empty = isempty(input.text)
  text = Text(empty ? input.placeholder : input.text,
              size=text_size(input), family=family(input), wrap=WrapMode.none,
              color=empty ? something(input.placeholder_color, theme(input).dim) : ink(input))
  Row(width(grow=GrowType.Grow), clip_x=true, Box(offset_x=-follow_caret!(input), text))
end

"Move the text sideways so that the caret is in view. It returns how far left the text has moved."
follow_caret!(input::TextInput) = begin
  isempty(input.text) && return input.scroll = 0px
  (focused(input) || input.scroll > 0px) || return input.scroll
  view = text_view(input)
  view === nothing && return input.scroll
  room = max(0px, view.width - 2px)   # the caret needs a little room at the right edge
  if focused(input)
    caret = width_to(input, input.cursor)
    input.scroll = clamp(input.scroll, max(0px, caret - room), caret)
  end
  input.scroll = clamp(input.scroll, 0px, max(0px, width_to(input, length(input.text)) - room))
end

describe(input::TextInput) = begin
  # The caret blinks, so the window has to draw again while the field has the keyboard
  focused(input) && redraw_in!(input, 0.5)
  input.look === nothing || return input.look(input, content(input))
  Row(width(grow=GrowType.Grow), height(36px * scale(theme(input))),
    padding(8px * scale(theme(input))),
    border(1px, :solid, theme(input).line),
    radius(4px),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), content(input)))
end

"The text that's in the field"
integrate(input::TextInput) = input.text

has_selection(input::TextInput) = input.anchor != input.cursor
selection_range(input::TextInput) = (min(input.cursor, input.anchor), max(input.cursor, input.anchor))
touch!(input::TextInput) = (input.last_action = time(); nothing)

# Get the first n characters of a string (0 returns "")
head(s::String, n::Int) = String(first(s, n))
# Get everything after the first n characters
tail(s::String, n::Int) = String(last(s, max(0, length(s) - n)))

"The text that's selected"
selection(input::TextInput) = ((lo, hi) = selection_range(input); head(tail(input.text, lo), hi - lo))

delete_selection!(input::TextInput) = begin
  lo, hi = selection_range(input)
  input.text = head(input.text, lo) * tail(input.text, hi)
  input.cursor = lo
  input.anchor = lo
  touch!(input)
end

"Put `s` where the caret is, in place of anything that's selected"
type!(input::TextInput, s::AbstractString) = begin
  has_selection(input) && delete_selection!(input)
  input.text = head(input.text, input.cursor) * s * tail(input.text, input.cursor)
  input.cursor += length(s)
  input.anchor = input.cursor
  touch!(input)
end

"Move the caret to `pos`. With `extend` the selection grows or shrinks to reach it."
move!(input::TextInput, pos::Int, extend::Bool=false) = begin
  input.cursor = clamp(pos, 0, length(input.text))
  extend || (input.anchor = input.cursor)
  touch!(input)
end

"Delete the characters from `lo` to `hi`, and leave the caret there"
cut!(input::TextInput, lo::Int, hi::Int) = begin
  input.cursor, input.anchor = lo, hi
  delete_selection!(input)
end

# --- words ---

isword(c::Char) = isletter(c) || isnumeric(c) || c == '_'

"Where the word before the caret starts"
word_start(input::TextInput, pos=input.cursor) = begin
  chars = collect(input.text)
  while pos > 0 && !isword(chars[pos]); pos -= 1 end
  while pos > 0 && isword(chars[pos]); pos -= 1 end
  pos
end

"Where the word after the caret ends"
word_end(input::TextInput, pos=input.cursor) = begin
  chars = collect(input.text)
  n = length(chars)
  while pos < n && !isword(chars[pos + 1]); pos += 1 end
  while pos < n && isword(chars[pos + 1]); pos += 1 end
  pos
end

"Select the word that `pos` is in or beside"
select_word!(input::TextInput, pos::Int) = begin
  chars = collect(input.text)
  lo = hi = pos
  while lo > 0 && isword(chars[lo]); lo -= 1 end
  while hi < length(chars) && isword(chars[hi + 1]); hi += 1 end
  input.anchor, input.cursor = lo, hi
  touch!(input)
end

# --- keyboard handler ---

# The key that goes with A, C, X and V: Cmd on a Mac and Ctrl elsewhere
const command = Sys.isapple() ? Keys.cmd : Keys.ctrl

"""
Do what `key` does in a text field. It returns `handled` when the key did
something here, so that the nodes above don't act on it too. Keys it has no use
for, like Enter, Escape and the up and down arrows, go on up to them.
"""
handle_key!(input::TextInput, key, window) = begin
  shift = Keys.shft in window.keys
  cmd = command in window.keys
  word = Keys.opt in window.keys
  n = length(input.text)
  if cmd && key == Keys.a
    input.anchor = 0
    move!(input, n, true)
  elseif cmd && key == Keys.c
    has_selection(input) && clipboard!(window, selection(input))
  elseif cmd && key == Keys.x
    has_selection(input) && (clipboard!(window, selection(input)); delete_selection!(input))
  elseif cmd && key == Keys.v
    # A field holds one line, so the lines of what's pasted are joined with spaces
    type!(input, replace(clipboard(window), r"\r?\n|\r" => " "))
  elseif key == Keys.left
    if cmd
      move!(input, 0, shift)
    elseif word
      move!(input, word_start(input), shift)
    elseif has_selection(input) && !shift
      move!(input, selection_range(input)[1])
    else
      move!(input, input.cursor - 1, shift)
    end
  elseif key == Keys.right
    if cmd
      move!(input, n, shift)
    elseif word
      move!(input, word_end(input), shift)
    elseif has_selection(input) && !shift
      move!(input, selection_range(input)[2])
    else
      move!(input, input.cursor + 1, shift)
    end
  elseif key == Keys.home
    move!(input, 0, shift)
  elseif key == Keys._end
    move!(input, n, shift)
  elseif key == Keys.backspace
    if has_selection(input)
      delete_selection!(input)
    elseif input.cursor > 0
      cut!(input, cmd ? 0 : word ? word_start(input) : input.cursor - 1, input.cursor)
    end
  elseif key == Keys.delete
    if has_selection(input)
      delete_selection!(input)
    elseif input.cursor < n
      cut!(input, input.cursor, word ? word_end(input) : input.cursor + 1)
    end
  else
    return nothing
  end
  handled
end

# --- finding a character from a place on screen ---

"The text of the field in the last layout, or `nothing` if it hasn't been laid out"
find_concrete_text(::Nothing) = nothing
find_concrete_text(tree::ConcreteText) = tree
find_concrete_text(tree::ConcreteRect) = begin
  for child in tree.children
    result = find_concrete_text(child)
    result !== nothing && return result
  end
  nothing
end

"The box that the text shows through in the last layout: the one that cuts it off at the left and right"
text_view(input::TextInput) = begin
  ct = find_concrete_text(rect(input))
  ct === nothing ? nothing : ct.parent.parent
end

"Which gap between characters is nearest to `x`, a place across the window. 0 is before the first character."
index_at(input::TextInput, x::px) = begin
  ct = find_concrete_text(rect(input))
  (ct === nothing || isempty(input.text)) && return 0
  x -= ct.left
  before = 0px
  for i in 1:length(input.text)
    after = width_to(input, i)
    x < (before + after) / 2 && return i - 1
    before = after
  end
  length(input.text)
end

# --- event handlers ---

cursor(::TextInput) = :ibeam

# A click gives the field the keyboard and puts the caret where it lands. A second click in the
# same place, soon after, selects the word there. With Shift it selects from where the caret was.
onkey(input::TextInput, e::KeyPress{Keys.mouse_left}) = begin
  focus(input)
  pos = index_at(input, e.window.mouse[1])
  input.picked_word = time() - input.last_click < 0.4 && pos == input.cursor && !has_selection(input)
  input.picked_word ? select_word!(input, pos) : move!(input, pos, Keys.shft in e.window.keys)
  input.last_click = time()
  handled
end
onkey(input::TextInput, e::KeyPress{K}) where K = handle_key!(input, K, e.window)
# Dragging selects from where the button went down. After a double click the word stays selected.
onmouse(input::TextInput, e::MouseMove) = begin
  Keys.mouse_left in e.window.keys || return
  input.picked_word || move!(input, index_at(input, e.position[1]), true)
  handled   # the drag is the field's, so the nodes above don't act on it too
end

# What the keyboard types goes in at the caret
ontype(input::TextInput, e::Typed) = begin
  iscntrl(e.char) && return nothing
  type!(input, string(e.char))
  handled
end

# --- the caret and the selection ---

"True when key presses go to `input`. Only then does it show a caret."
focused(input::TextInput) = (w = window_of(input); w !== nothing && w.focus === input)

"True for the half of each second that the caret shows. It always shows just after a key press."
caret_shows(input::TextInput) = (elapsed = time() - input.last_action; elapsed < 0.5 || mod(elapsed - 0.5, 1.0) < 0.5)

draw(ctx, size, ui::ConcreteRect, input::TextInput) = begin
  ct = find_concrete_text(ui)
  ct === nothing && return
  m = font_metrics(font(input))
  baseline = ct.top + px(m.capHeight)   # where the renderer puts it
  top, bottom = baseline + px(m.ascent), baseline + px(m.descent)
  view = ct.parent.parent
  # The selection and the caret are cut off where the text is
  with_clip(ctx, view.left - 1px, top, view.width + 2px, bottom - top) do
    if has_selection(input)
      lo, hi = selection_range(input)
      x = ct.left + width_to(input, lo)
      rectangle(ctx, x, top, ct.left + width_to(input, hi) - x, bottom - top, background=RGBA(0.26, 0.52, 0.96, 0.3), border=0px)
    end
    if focused(input) && caret_shows(input)
      x = ct.left + (isempty(input.text) ? 0px : width_to(input, input.cursor))
      line(ctx, Vec2{px}(x, top), Vec2{px}(x, bottom), 1.5px, ink(input))
    end
  end
end

export TextInput, describe
