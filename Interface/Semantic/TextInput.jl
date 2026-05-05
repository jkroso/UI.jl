@use "github.com/jkroso/Prospects.jl" @def @property
@use "github.com/jkroso/MiniFB.jl/skia" SkiaFont measure_text rectangle line font_metrics
@use "github.com/jkroso/MiniFB.jl" Window Keys KeyPress MouseMove onkey onmouse int
@use "github.com/jkroso/Font.jl" Font ["units" pt px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe
@use "../draw" draw
@use Colors: @colorant_str, Colorant, RGBA
@use GeometryBasics: Vec2

@def mutable struct TextInput <: SemanticUI
  text::String = ""
  cursor::Int = 0         # 0-based: 0=before first char, n=after nth char
  anchor::Int = 0         # selection anchor; equals cursor when no selection
  last_action::Float64 = time()
  # config
  font_family::String = "Helvetica"
  font_size::pt = 14pt
  placeholder::String = "Type here..."
  # cached layout (updated each frame for mouse hit-testing)
  cached_left::px = 0px
  cached_top::px = 0px
  cached_ascent::px = 0px    # negative (above baseline)
  cached_descent::px = 0px   # positive (below baseline)
  cached_capheight::px = 0px # baseline = ct.top + capHeight (matches the renderer)
  cached_font::Union{Nothing,SkiaFont} = nothing
end

describe(input::TextInput) = begin
  empty = isempty(input.text)
  Row(width(grow=GrowType.Grow), height(36px),
    padding(8px),
    border(1px, :solid, colorant"rgb(180,180,180)"),
    radius(4px),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Text(empty ? input.placeholder : input.text,
           size=input.font_size, family=input.font_family,
           color=empty ? colorant"rgb(160,160,160)" : colorant"rgb(30,30,30)")))
end

has_selection(input::TextInput) = input.anchor != input.cursor
selection_range(input::TextInput) = (min(input.cursor, input.anchor), max(input.cursor, input.anchor))
touch!(input::TextInput) = (input.last_action = time(); nothing)

# Get the first n characters of a string (0 returns "")
head(s::String, n::Int) = n == 0 ? "" : String(collect(s)[1:n])
# Get everything after the first n characters
tail(s::String, n::Int) = n >= length(s) ? "" : String(collect(s)[n+1:end])

delete_selection!(input::TextInput) = begin
  lo, hi = selection_range(input)
  input.text = head(input.text, lo) * tail(input.text, hi)
  input.cursor = lo
  input.anchor = lo
  touch!(input)
end

# --- keychar map ---

const keychar = Dict{Keys,Char}()
for c in 'a':'z'; keychar[getproperty(Keys, Symbol(c))] = c end
for d in 0:9; keychar[getproperty(Keys, Symbol(d))] = Char('0' + d) end
keychar[Keys.space] = ' '
keychar[Keys.period] = '.'
keychar[Keys.comma] = ','
keychar[Keys.minus] = '-'
keychar[Keys.apostrophe] = '\''
keychar[Keys.semicolon] = ';'
keychar[Keys.slash] = '/'
keychar[Keys.equal] = '='
keychar[Keys.left_bracket] = '['
keychar[Keys.right_bracket] = ']'
keychar[Keys.backslash] = '\\'

# --- keyboard handler ---

handle_key!(input::TextInput, key, window) = begin
  shift = Keys.shft in window.keys
  cmd = Keys.cmd in window.keys
  n = length(input.text)
  if cmd && key == Keys.a
    input.anchor = 0
    input.cursor = n
    touch!(input)
  elseif key == Keys.left
    if shift
      input.cursor = max(0, input.cursor - 1)
    elseif has_selection(input)
      lo, _ = selection_range(input)
      input.cursor = lo
      input.anchor = lo
    else
      input.cursor = max(0, input.cursor - 1)
      input.anchor = input.cursor
    end
    touch!(input)
  elseif key == Keys.right
    if shift
      input.cursor = min(n, input.cursor + 1)
    elseif has_selection(input)
      _, hi = selection_range(input)
      input.cursor = hi
      input.anchor = hi
    else
      input.cursor = min(n, input.cursor + 1)
      input.anchor = input.cursor
    end
    touch!(input)
  elseif key == Keys.backspace
    if has_selection(input)
      delete_selection!(input)
    elseif input.cursor > 0
      input.text = head(input.text, input.cursor - 1) * tail(input.text, input.cursor)
      input.cursor -= 1
      input.anchor = input.cursor
      touch!(input)
    end
  elseif key == Keys.delete
    if has_selection(input)
      delete_selection!(input)
    elseif input.cursor < n
      input.text = head(input.text, input.cursor) * tail(input.text, input.cursor + 1)
      touch!(input)
    end
  elseif haskey(keychar, key)
    has_selection(input) && delete_selection!(input)
    c = keychar[key]
    c = shift ? uppercase(c) : c
    input.text = head(input.text, input.cursor) * c * tail(input.text, input.cursor)
    input.cursor += 1
    input.anchor = input.cursor
    touch!(input)
  end
end

# --- character measurement ---

char_offsets(text::String, font::SkiaFont) = begin
  offsets = px[0px]
  for i in 1:length(text)
    w, _ = measure_text(font, first(text, i))
    push!(offsets, px(w))
  end
  offsets
end

char_at_x(text::String, font::SkiaFont, relative_x::px) = begin
  offsets = char_offsets(text, font)
  for i in 1:length(text)
    mid = (offsets[i] + offsets[i+1]) / 2
    relative_x < mid && return i - 1
  end
  length(text)
end

# --- mouse handlers ---

handle_click!(input::TextInput, mouse_x::px) = begin
  font = input.cached_font
  isnothing(font) && return
  relative_x = mouse_x - input.cached_left
  pos = isempty(input.text) ? 0 : char_at_x(input.text, font, relative_x)
  input.cursor = pos
  input.anchor = pos
  touch!(input)
end

handle_drag!(input::TextInput, mouse_x::px) = begin
  font = input.cached_font
  isnothing(font) && return
  relative_x = mouse_x - input.cached_left
  pos = isempty(input.text) ? 0 : char_at_x(input.text, font, relative_x)
  input.cursor = pos
  touch!(input)
end

# --- event handlers ---

onkey(input::TextInput, e::KeyPress{Keys.mouse_left}) = handle_click!(input, e.window.mouse[1])
onkey(input::TextInput, e::KeyPress{K}) where K = handle_key!(input, K, e.window)
onmouse(input::TextInput, e::MouseMove) = Keys.mouse_left in e.window.keys && handle_drag!(input, e.position[1])

# --- overlay drawing ---

draw_cursor(ctx, input::TextInput, ct::ConcreteText, offsets) = begin
  elapsed = time() - input.last_action
  visible = elapsed < 0.5 || mod(elapsed - 0.5, 1.0) < 0.5
  visible || return
  x = ct.left + offsets[input.cursor + 1]
  baseline = ct.top + input.cached_capheight
  top = baseline + input.cached_ascent
  bot = baseline + input.cached_descent
  line(ctx, Vec2{px}(x, top), Vec2{px}(x, bot), 1.5px, colorant"rgb(30,30,30)")
end

draw_selection(ctx, input::TextInput, ct::ConcreteText, offsets) = begin
  has_selection(input) || return
  lo, hi = selection_range(input)
  x1 = ct.left + offsets[lo + 1]
  x2 = ct.left + offsets[hi + 1]
  baseline = ct.top + input.cached_capheight
  top = baseline + input.cached_ascent
  h = input.cached_descent - input.cached_ascent
  rectangle(ctx, x1, top, x2 - x1, h, background=RGBA(0.26, 0.52, 0.96, 0.3), border=0px)
end

draw_overlay(ctx, input::TextInput, ct::ConcreteText) = begin
  isempty(input.text) && !has_selection(input) && return draw_empty_cursor(ctx, input, ct)
  font = input.cached_font
  isnothing(font) && return
  offsets = char_offsets(input.text, font)
  draw_selection(ctx, input, ct, offsets)
  draw_cursor(ctx, input, ct, offsets)
end

draw_empty_cursor(ctx, input::TextInput, ct::ConcreteText) = begin
  elapsed = time() - input.last_action
  visible = elapsed < 0.5 || mod(elapsed - 0.5, 1.0) < 0.5
  visible || return
  x = ct.left
  baseline = ct.top + input.cached_capheight
  top = baseline + input.cached_ascent
  bot = baseline + input.cached_descent
  line(ctx, Vec2{px}(x, top), Vec2{px}(x, bot), 1.5px, colorant"rgb(30,30,30)")
end

find_concrete_text(tree::ConcreteText) = tree
find_concrete_text(tree::ConcreteRect) = begin
  for child in tree.children
    result = find_concrete_text(child)
    result !== nothing && return result
  end
  nothing
end

update_cache!(input::TextInput, ct::ConcreteText) = begin
  input.cached_left = ct.left
  input.cached_top = ct.top
  font = SkiaFont(input.font_family, input.font_size)
  input.cached_font = font
  m = font_metrics(font)
  input.cached_ascent = px(m.ascent)
  input.cached_descent = px(m.descent)
  input.cached_capheight = px(m.capHeight)
end

draw(ctx, size, ui::ConcreteRect, input::TextInput) = begin
  ct = find_concrete_text(ui)
  ct === nothing && return
  update_cache!(input, ct)
  draw_overlay(ctx, input, ct)
end

export TextInput, describe
