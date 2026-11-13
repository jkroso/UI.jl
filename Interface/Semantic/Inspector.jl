@use "github.com/jkroso/Prospects.jl" @def @abstract
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" UITree SemanticUI describe mixin! add_child! describe! focus onblur window_of theme scale handled sized
@use "../draw" draw cursor
@use "./Icon" Icon
@use "./TextInput" TextInput text_size
@use Colors: @colorant_str

# --- Types ---

@abstract struct DataView <: SemanticUI
  label::String = ""
  parent_data::Any = nothing
  data_key::Any = nothing
end

@def mutable struct LeafView <: DataView
  data::Any = nothing
  editing::Bool = false
  editor::Union{Nothing,TextInput} = nothing
end

@def mutable struct CollectionView <: DataView
  data::Any = nothing
  collapsed::Bool = true
end

@def mutable struct Inspector <: SemanticUI
  focused::Union{Nothing,DataView} = nothing
end

Inspector(view::DataView) = begin
  ins = Inspector()
  add_child!(ins, view)
  ins.focused = view
  ins
end

# --- inspect() dispatch ---

inspect(x::Bool; kw...) = LeafView(; data=x, kw...)
inspect(x::Number; kw...) = LeafView(; data=x, kw...)
inspect(x::AbstractString; kw...) = LeafView(; data=x, kw...)
inspect(x::Symbol; kw...) = LeafView(; data=x, kw...)
inspect(::Nothing; kw...) = LeafView(; data=nothing, kw...)
inspect(x::Char; kw...) = LeafView(; data=x, kw...)
inspect(x::Type; kw...) = LeafView(; data=x, kw...)

inspect(d::AbstractDict; kw...) = begin
  cv = CollectionView(; data=d, kw...)
  for (k, v) in d
    add_child!(cv, inspect(v, label=string(k), parent_data=d, data_key=k))
  end
  cv
end

inspect(t::Tuple; kw...) = begin
  cv = CollectionView(; data=t, kw...)
  for (i, v) in enumerate(t)
    add_child!(cv, inspect(v, label=string(i), parent_data=t, data_key=i))
  end
  cv
end

inspect(t::NamedTuple; kw...) = begin
  cv = CollectionView(; data=t, kw...)
  for k in keys(t)
    add_child!(cv, inspect(t[k], label=string(k), parent_data=t, data_key=k))
  end
  cv
end

inspect(a::AbstractArray; kw...) = begin
  cv = CollectionView(; data=a, kw...)
  for (i, v) in enumerate(a)
    add_child!(cv, inspect(v, label=string(i), parent_data=a, data_key=i))
  end
  cv
end

inspect(s::AbstractSet; kw...) = begin
  cv = CollectionView(; data=s, kw...)
  for v in s
    add_child!(cv, inspect(v))
  end
  cv
end

# Fallback: any struct
inspect(x; kw...) = begin
  T = typeof(x)
  fnames = fieldnames(T)
  isempty(fnames) && return LeafView(; data=x, kw...)
  cv = CollectionView(; data=x, kw...)
  for fn in fnames
    val = getfield(x, fn)
    add_child!(cv, inspect(val, label=string(fn), parent_data=x, data_key=fn))
  end
  cv
end

# --- type_brief ---

type_brief(d::AbstractDict) = "Dict{$(eltype(keys(d))),$(eltype(values(d)))}[$(length(d))]"
type_brief(::Tuple{}) = "Tuple[0]"
type_brief(t::Tuple) = "Tuple[$(length(t))]"
type_brief(t::NamedTuple) = "NamedTuple[$(length(t))]"
type_brief(a::AbstractArray) = "$(nameof(typeof(a))){$(eltype(a))}[$(length(a))]"
type_brief(s::AbstractSet) = "Set{$(eltype(s))}[$(length(s))]"
type_brief(x) = begin
  T = typeof(x)
  n = length(fieldnames(T))
  "$(nameof(T))[$n]"
end

# --- format_value ---

# The text of a value, and its colour from the theme

format_value(x::Number)         = (string(x), theme().number)
format_value(x::AbstractString) = ("\"$x\"", theme().string)
format_value(x::Symbol)         = (":$x", theme().symbol)
format_value(x::Bool)           = (string(x), theme().keyword)
format_value(::Nothing)         = ("nothing", theme().dim)
format_value(x::Char)           = ("'$x'", theme().string)
format_value(x::Type)           = (string(x), theme().type)
format_value(x)                 = (repr(x), theme().text)

"The marks around a value's text while it's edited: the quotes of a string or a character, and the colon of a symbol"
marks(::AbstractString) = ("\"", "\"")
marks(::Char)           = ("'", "'")
marks(::Symbol)         = (":", "")
marks(_)                = ("", "")

# --- editability ---

is_editable(dv::DataView) = begin
  dv.parent_data === nothing && return false
  pd = dv.parent_data
  pd isa AbstractDict && return true
  pd isa AbstractArray && return true
  ismutabletype(typeof(pd))
end

# --- write_back! ---

write_back!(dv::DataView, new_val) = begin
  pd = dv.parent_data
  pd === nothing && return
  k = dv.data_key
  if pd isa AbstractDict
    pd[k] = new_val
  elseif pd isa AbstractArray
    pd[k] = new_val
  elseif ismutabletype(typeof(pd))
    T = fieldtype(typeof(pd), k)
    setfield!(pd, k, convert(T, new_val))
  end
  dv.data = new_val
end

# --- parse_value ---

parse_value(old::Bool, text::String) = lowercase(text) in ("true", "1") ? true : false
parse_value(old::Integer, text::String) = parse(typeof(old), text)
parse_value(old::AbstractFloat, text::String) = parse(typeof(old), text)
parse_value(old::Number, text::String) = parse(typeof(old), text)
parse_value(::AbstractString, text::String) = text
parse_value(::Symbol, text::String) = Symbol(text)
parse_value(::Char, text::String) = isempty(text) ? ' ' : first(text)
parse_value(old, text::String) = text

# --- Navigation ---

"Next visible DataView in depth-first order"
next_visible(item::DataView) = begin
  if item isa CollectionView && !item.collapsed
    for child in item.children
      child isa DataView && return child
    end
  end
  sib = item.nextsibling
  while sib !== nothing
    sib isa DataView && return sib
    sib = sib.nextsibling
  end
  node = item.parent
  while node !== nothing && !(node isa Inspector)
    sib = node.nextsibling
    while sib !== nothing
      sib isa DataView && return sib
      sib = sib.nextsibling
    end
    node = node.parent
  end
  nothing
end

"Previous visible DataView in depth-first order"
prev_visible(item::DataView) = begin
  prev = item.prevsibling
  while prev !== nothing && !(prev isa DataView)
    prev = prev.prevsibling
  end
  prev !== nothing && return last_visible(prev)
  p = item.parent
  p isa DataView ? p : nothing
end

"Last visible descendant"
last_visible(item::LeafView) = item
last_visible(item::CollectionView) = begin
  item.collapsed && return item
  last = nothing
  for child in item.children
    child isa DataView && (last = child)
  end
  last === nothing ? item : last_visible(last)
end

# --- Describe ---

const INDENT_WIDTH = 20px
const ROW_HEIGHT = 28px
const ROW_PADDING = 8px    # between a row's text and the ends of its highlight
const FRAME_PADDING = 6px  # between the rows and the frame's border
const LABEL_GAP = 6px      # between a label's colon and its value
const CHEVRON_WIDTH = 12px
const CHEVRON_GAP = 4px

describe(ins::Inspector) = begin
  col = Column(width(grow=GrowType.Grow), padding(FRAME_PADDING * scale()),
               radius(6px), border(1px, :solid, theme(ins).line),
               background(theme(ins).surface))
  root = ins.firstchild
  root !== nothing && flatten_views!(col, root, 0, ins.focused)
  col
end

flatten_views!(col, cv::CollectionView, depth, focused) = begin
  mixin!(col, describe_row(cv, depth, focused))
  cv.collapsed && return
  for child in cv.children
    child isa DataView || continue
    if child isa CollectionView
      flatten_views!(col, child, depth + 1, focused)
    else
      mixin!(col, describe_row(child, depth + 1, focused))
    end
  end
end

flatten_views!(col, lv::LeafView, depth, focused) = mixin!(col, describe_row(lv, depth, focused))

"A row with its highlight, its indent and its label. The caller adds the value."
row_start(dv::DataView, depth, focused) = begin
  k = scale()
  row = Row(width(grow=GrowType.Grow), height(ROW_HEIGHT * k), padding(ROW_PADDING * k, 0px), Alignment.Center)
  row.from = dv
  dv === focused && mixin!(row, background(theme().select), radius(4px * k))
  depth > 0 && mixin!(row, Box(width(INDENT_WIDTH * depth * k)))
  if !isempty(dv.label)
    mixin!(row, Box(height(grow=GrowType.Grow), Alignment.Center,
                    Text(dv.label * ":", size=sized(12pt), color=theme().dim)))
    mixin!(row, Box(width(LABEL_GAP * k)))
  end
  row
end

describe_row(cv::CollectionView, depth, focused) = begin
  k = scale()
  row = row_start(cv, depth, focused)
  name = cv.collapsed ? "chevron-right" : "chevron-down"
  mixin!(row, Box(width(CHEVRON_WIDTH * k), height(ROW_HEIGHT * k), Alignment.Center,
                  describe!(Icon(name, size=12px * k, color=theme().dim))))
  mixin!(row, Box(width(CHEVRON_GAP * k)))
  mixin!(row, Box(height(grow=GrowType.Grow), Alignment.Center,
                  Text(type_brief(cv.data), size=sized(11pt), color=theme().dim)))
  row
end

describe_row(lv::LeafView, depth, focused) = begin
  row = row_start(lv, depth, focused)
  text, color = format_value(lv.data)
  if lv.editing && lv.editor !== nothing
    lv.editor.color = color   # what's typed has the colour of the value it will be
    mixin!(row, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), describe!(lv.editor)))
  else
    mixin!(row, Box(height(grow=GrowType.Grow), Alignment.Center,
                    Text(text, size=sized(12pt), color=color)))
  end
  row
end

# --- Events ---

find_inspector(node) = node isa Inspector ? node : find_inspector(node.parent)

start_editing!(lv::LeafView) = begin
  text = if lv.data isa AbstractString
    lv.data
  elseif lv.data isa Char
    string(lv.data)
  elseif lv.data isa Symbol
    string(lv.data)
  else
    string(lv.data)
  end
  editor = TextInput(text=text, placeholder="", font_size=12pt, look=edit_look(lv))
  lv.editor = editor
  add_child!(lv, editor)
  lv.editing = true
  focus(editor)
end

"Keep what's typed, if it reads as a value of the same kind, and stop editing"
finish_edit!(lv::LeafView) = begin
  lv.editor === nothing && return
  try
    write_back!(lv, parse_value(lv.data, lv.editor.text))
  catch
  end
  lv.editing = false
  lv.editor = nothing
end

"""
How the field looks while a value is edited: like the value, with no border. A string keeps its
quotes, which you can't delete, and the closing quote follows the text as it gets longer.
"""
edit_look(lv::LeafView) = (input, text) -> begin
  before, after = marks(lv.data)
  colour = something(input.color, theme(input).text)
  # The text is as wide as it is, and 2px more for the caret after the last character.
  # It still gets narrower and scrolls when the row runs out of room.
  mixin!(text, width(grow=GrowType.FitContent), padding(0px, 2px, 0px, 0px))
  # Each mark is in a box, so that it doesn't grow into the row's spare room the way text does
  mark(s) = Box(Text(s, size=text_size(input), color=colour))
  row = Row(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Center, clip=true)
  isempty(before) || mixin!(row, mark(before))
  mixin!(row, text)
  isempty(after) || mixin!(row, mark(after))
  row
end

commit_edit!(ins::Inspector, lv::LeafView) = (finish_edit!(lv); focus(ins))

# A click on anything else that takes the keyboard ends the edit, and keeps what was typed
onblur(lv::LeafView, from) = from === lv.editor ? (finish_edit!(lv); handled) : nothing

cancel_edit!(ins::Inspector, lv::LeafView) = begin
  lv.editing = false
  lv.editor = nothing
  focus(ins)
end

# Mouse clicks. The view that's clicked takes the click, so the views it's in don't act on it too

# A click opens or closes a collection and flips a true or a false. In any other value you can change, it puts a caret.
cursor(::CollectionView) = :hand
cursor(lv::LeafView) = !is_editable(lv) ? :arrow : lv.data isa Bool ? :hand : :ibeam

onkey(cv::CollectionView, ::KeyPress{Keys.mouse_left}) = begin
  ins = find_inspector(cv)
  ins.focused = cv
  focus(ins)
  cv.collapsed = !cv.collapsed
  handled
end

onkey(lv::LeafView, ::KeyPress{Keys.mouse_left}) = begin
  ins = find_inspector(lv)
  ins.focused = lv
  if is_editable(lv) && lv.data isa Bool
    write_back!(lv, !lv.data)
    focus(ins)
  elseif is_editable(lv) && !lv.editing
    start_editing!(lv)
  else
    focus(ins)
  end
  handled
end

# Keyboard navigation. While a value is being edited its field has the keyboard, and the arrow
# keys it doesn't use come up to here. They stay in the field until Escape or Enter ends the edit.

"Whether the inspector has the keyboard itself, and not the field of a value that's being edited"
has_keyboard(ins::Inspector) = (w = window_of(ins); w !== nothing && w.focus === ins)

onkey(ins::Inspector, ::KeyPress{Keys.down}) = begin
  has_keyboard(ins) || return handled
  ins.focused === nothing && return
  next = next_visible(ins.focused)
  next !== nothing && (ins.focused = next)
end

onkey(ins::Inspector, ::KeyPress{Keys.up}) = begin
  has_keyboard(ins) || return handled
  ins.focused === nothing && return
  prev = prev_visible(ins.focused)
  prev !== nothing && (ins.focused = prev)
end

onkey(ins::Inspector, ::KeyPress{Keys.right}) = begin
  has_keyboard(ins) || return handled
  item = ins.focused
  item === nothing && return
  if item isa CollectionView
    if item.collapsed
      item.collapsed = false
    else
      for child in item.children
        child isa DataView && (ins.focused = child; break)
      end
    end
  end
end

onkey(ins::Inspector, ::KeyPress{Keys.left}) = begin
  has_keyboard(ins) || return handled
  item = ins.focused
  item === nothing && return
  if item isa CollectionView && !item.collapsed
    item.collapsed = true
  elseif item.parent isa DataView
    ins.focused = item.parent
  end
end

# Enter keeps an edit, opens or closes a collection, or starts editing a value. A key that the
# inspector uses doesn't go on to the nodes it's in.
onkey(ins::Inspector, ::KeyPress{Keys.enter}) = begin
  item = ins.focused
  item === nothing && return
  if item isa LeafView && item.editing
    commit_edit!(ins, item)
  elseif item isa CollectionView
    item.collapsed = !item.collapsed
  elseif item isa LeafView && is_editable(item)
    item.data isa Bool ? write_back!(item, !item.data) : start_editing!(item)
  else
    return
  end
  handled
end

# Escape drops an edit, and the inspector keeps the keyboard so the arrow keys move through it again.
# Escape when nothing is being edited goes on to the nodes the inspector is in, so that an app can
# take the keyboard back.
onkey(ins::Inspector, ::KeyPress{Keys.escape}) = begin
  item = ins.focused
  item isa LeafView && item.editing || return
  cancel_edit!(ins, item)
  handled
end

export Inspector, inspect, DataView, LeafView, CollectionView
