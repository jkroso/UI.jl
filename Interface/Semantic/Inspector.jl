@use "github.com/jkroso/Prospects.jl" @def @abstract
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" UITree SemanticUI describe mixin! add_child! describe! focus
@use "../draw" draw
@use "./Icon" Icon
@use "./TextInput" TextInput
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

const COLOR_NUMBER  = colorant"rgb(0,150,136)"
const COLOR_STRING  = colorant"rgb(211,47,47)"
const COLOR_SYMBOL  = colorant"rgb(63,81,181)"
const COLOR_BOOL    = colorant"rgb(142,36,170)"
const COLOR_NOTHING = colorant"rgb(130,130,130)"
const COLOR_TYPE    = colorant"rgb(63,81,181)"
const COLOR_DEFAULT = colorant"rgb(80,80,80)"
const COLOR_LABEL   = colorant"rgb(100,100,100)"
const COLOR_BRIEF   = colorant"rgb(130,130,130)"

format_value(x::Number)         = (string(x), COLOR_NUMBER)
format_value(x::AbstractString) = ("\"$x\"", COLOR_STRING)
format_value(x::Symbol)         = (":$x", COLOR_SYMBOL)
format_value(x::Bool)           = (string(x), COLOR_BOOL)
format_value(::Nothing)         = ("nothing", COLOR_NOTHING)
format_value(x::Char)           = ("'$x'", COLOR_STRING)
format_value(x::Type)           = (string(x), COLOR_TYPE)
format_value(x)                 = (repr(x), COLOR_DEFAULT)

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
const CHEVRON_WIDTH = 12px
const CHEVRON_GAP = 3px
const FOCUS_BG = colorant"rgb(210,222,240)"

describe(ins::Inspector) = begin
  ins.state = nothing # reset click-consumed flag
  col = Column(width(grow=GrowType.Grow), padding(6px, 4px),
               radius(6px), border(1px, :solid, colorant"rgb(200,200,200)"),
               background(colorant"white"))
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

describe_row(cv::CollectionView, depth, focused) = begin
  row = Row(width(grow=GrowType.Grow), height(ROW_HEIGHT), Alignment.Center)
  row.from = cv
  cv === focused && mixin!(row, background(FOCUS_BG), radius(4px))
  # indent
  depth > 0 && mixin!(row, Box(width(INDENT_WIDTH * depth)))
  # label
  if !isempty(cv.label)
    mixin!(row, Box(height(grow=GrowType.Grow), Alignment.Center,
                    Text(cv.label * ": ", size=12pt, color=COLOR_LABEL)))
  end
  # chevron
  name = cv.collapsed ? "chevron-right" : "chevron-down"
  mixin!(row, Box(width(CHEVRON_GAP)))
  mixin!(row, Box(width(CHEVRON_WIDTH), height(ROW_HEIGHT), Alignment.Center,
                  describe!(Icon(name, size=12px, color=colorant"rgb(150,150,150)"))))
  mixin!(row, Box(width(CHEVRON_GAP)))
  # type brief
  mixin!(row, Box(height(grow=GrowType.Grow), Alignment.Center,
                  Text(type_brief(cv.data), size=11pt, color=COLOR_BRIEF)))
  row
end

describe_row(lv::LeafView, depth, focused) = begin
  row = Row(width(grow=GrowType.Grow), height(ROW_HEIGHT), Alignment.Center)
  row.from = lv
  lv === focused && mixin!(row, background(FOCUS_BG), radius(4px))
  # indent
  depth > 0 && mixin!(row, Box(width(INDENT_WIDTH * depth)))
  # label
  if !isempty(lv.label)
    mixin!(row, Box(height(grow=GrowType.Grow), Alignment.Center,
                    Text(lv.label * ": ", size=12pt, color=COLOR_LABEL)))
  end
  # value or editor
  if lv.editing && lv.editor !== nothing
    mixin!(row, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), describe!(lv.editor)))
  else
    text, color = format_value(lv.data)
    mixin!(row, Box(height(grow=GrowType.Grow), Alignment.Center,
                    Text(text, size=12pt, color=color)))
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
  editor = TextInput(text=text, placeholder="", font_size=12pt)
  lv.editor = editor
  add_child!(lv, editor)
  lv.editing = true
  focus(editor)
end

commit_edit!(ins::Inspector, lv::LeafView) = begin
  lv.editor === nothing && return
  try
    new_val = parse_value(lv.data, lv.editor.text)
    write_back!(lv, new_val)
  catch
  end
  lv.editing = false
  lv.editor = nothing
  focus(ins)
end

cancel_edit!(ins::Inspector, lv::LeafView) = begin
  lv.editing = false
  lv.editor = nothing
  focus(ins)
end

# Mouse clicks — consume flag prevents parent DataViews from also acting

onkey(cv::CollectionView, ::KeyPress{Keys.mouse_left}) = begin
  ins = find_inspector(cv)
  ins.state !== nothing && return
  ins.state = true
  ins.focused = cv
  focus(ins)
  cv.collapsed = !cv.collapsed
end

onkey(lv::LeafView, ::KeyPress{Keys.mouse_left}) = begin
  ins = find_inspector(lv)
  ins.state !== nothing && return
  ins.state = true
  ins.focused = lv
  if is_editable(lv) && lv.data isa Bool
    write_back!(lv, !lv.data)
    focus(ins)
  elseif is_editable(lv) && !lv.editing
    start_editing!(lv)
  else
    focus(ins)
  end
end

# Keyboard navigation (dispatched when Inspector is focused)

onkey(ins::Inspector, ::KeyPress{Keys.down}) = begin
  ins.focused === nothing && return
  next = next_visible(ins.focused)
  next !== nothing && (ins.focused = next)
end

onkey(ins::Inspector, ::KeyPress{Keys.up}) = begin
  ins.focused === nothing && return
  prev = prev_visible(ins.focused)
  prev !== nothing && (ins.focused = prev)
end

onkey(ins::Inspector, ::KeyPress{Keys.right}) = begin
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
  item = ins.focused
  item === nothing && return
  if item isa CollectionView && !item.collapsed
    item.collapsed = true
  elseif item.parent isa DataView
    ins.focused = item.parent
  end
end

# Enter: commit edit (bubbled from TextInput), toggle collection, or start editing
onkey(ins::Inspector, ::KeyPress{Keys.enter}) = begin
  item = ins.focused
  item === nothing && return
  if item isa LeafView && item.editing
    commit_edit!(ins, item)
  elseif item isa CollectionView
    item.collapsed = !item.collapsed
  elseif item isa LeafView && is_editable(item)
    item.data isa Bool ? write_back!(item, !item.data) : start_editing!(item)
  end
end

# Escape: cancel edit (bubbled from TextInput)
onkey(ins::Inspector, ::KeyPress{Keys.escape}) = begin
  item = ins.focused
  item === nothing && return
  item isa LeafView && item.editing && cancel_edit!(ins, item)
end

export Inspector, inspect, DataView, LeafView, CollectionView
