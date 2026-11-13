@use "github.com/jkroso/Prospects.jl" @abstract @def @property Field group assoc mixin_constructor mixin! ["Enum" @Enum]
@use "github.com/jkroso/Sequences.jl" ["collections/Map" Map]
@use "github.com/jkroso/Font.jl" Font ["units" pt px inch em]
@use "github.com/jkroso/Units.jl" Length mm cm m
@use Colors: Color, Colorant, RGB, RGBA, hex
@use NamingConventions

const black = parse(Colorant, "black")

abstract type StyleNode end

@abstract struct UI end
@abstract struct UITree <: UI
  parent::Union{Nothing,UITree}=nothing
  prevsibling::Union{Nothing,UITree}=nothing
  nextsibling::Union{Nothing,UITree}=nothing
end

# Opt UITree into Prospects' explicit-typed-inner emission so the abstract
# variadic `(::Type{T})(attrs...) where T <: UITree` defined below isn't
# shadowed by Julia's auto-generated convert outer when a call's arity
# happens to equal the field count of the concrete subtype (e.g.
# `Column(width, height, padding, background, ...11 children)` hitting the
# 13-field Container layout). Has to be declared *before* @def types that
# subtype UITree are defined, because deftype reads the trait at expansion.
mixin_constructor(::Type{<:UITree}) = true

"""
The colours and the font that components draw themselves with. A component
doesn't choose its own colours. It asks for `theme(node)` and uses the role
that fits, so the same component suits a white page, a sepia page and a dark
page. Each field is one role:
"""
Base.@kwdef struct Theme
  surface::Colorant = RGB(1.0, 1.0, 1.0)           # behind a component: a text field, a menu, a tree
  text::Colorant = RGB(0.0, 0.0, 0.0)              # labels and values
  dim::Colorant = RGB(0.47, 0.47, 0.47)            # less important text, arrows and icons
  line::Colorant = RGB(0.78, 0.78, 0.78)           # borders and rules
  track::Colorant = RGB(0.86, 0.86, 0.86)          # the empty part of a slider, a switch that's off
  hover::Colorant = RGB(0.95, 0.96, 0.97)          # behind what the mouse is over
  select::Colorant = RGB(0.82, 0.87, 0.94)         # behind the selected row
  accent::Colorant = RGB(0.23, 0.51, 0.96)         # a ticked box, a switch that's on, the full part of a slider
  on_accent::Colorant = RGB(1.0, 1.0, 1.0)         # what's drawn over the accent, like a tick or a knob
  family::String = "Helvetica"                     # the font of labels
  mono::String = "Menlo"                           # the font of code, and of names in a tree
  mono_style::String = ""                          # its weight or style, like "ExtraLight"
  size::Length = 12pt                              # the size of the names in a tree. See `scale`.
  # The kinds of value in code and in the inspector
  number::Colorant = RGB(0.0, 0.59, 0.53)
  string::Colorant = RGB(0.83, 0.18, 0.18)
  symbol::Colorant = RGB(0.25, 0.32, 0.71)
  keyword::Colorant = RGB(0.56, 0.14, 0.67)        # `true` and `false` too
  type::Colorant = RGB(0.25, 0.32, 0.71)
end

const light = Theme()
const dark = Theme(surface=RGB(0.17, 0.17, 0.19), text=RGB(0.88, 0.88, 0.86), dim=RGB(0.6, 0.6, 0.58),
                   line=RGB(0.3, 0.3, 0.32), track=RGB(0.28, 0.28, 0.3), hover=RGB(0.22, 0.22, 0.24),
                   select=RGB(0.24, 0.3, 0.42), accent=RGB(0.4, 0.62, 1.0),
                   number=RGB(0.9, 0.67, 0.39), string=RGB(0.63, 0.78, 0.47), symbol=RGB(0.47, 0.67, 0.98),
                   keyword=RGB(0.78, 0.51, 0.86), type=RGB(0.43, 0.78, 0.78))

# The theme that nodes described right now will get
const THEME = Base.ScopedValues.ScopedValue{Theme}(light)

"""
Describe everything that `f` makes with `theme`. Call it inside a `describe`
method, around the part of the UI that should have those colours:

    describe(app::App) = with_theme(app.night ? dark : light) do
      Column(Checkbox(label="Wrap lines"), Slider())
    end

Nodes inside can be given a different theme by another `with_theme`.
"""
with_theme(f, theme::Theme) = Base.ScopedValues.with(f, THEME => theme)

"""
The theme `node` was last described with. Use it in `describe`, in `draw` and
in event handlers. A node that wasn't described itself, like a row of a tree,
has the theme of the node it's in. Without a node it gives the theme being
described with now.
"""
theme() = THEME[]
theme(node) = begin
  while node !== nothing
    if node isa SemanticUI
      t = getfield(node, :inherited_theme)
      t === nothing || return t::Theme
    end
    node = node isa UITree ? getfield(node, :parent) : node.parent
  end
  THEME[]
end

# 12pt in pixels on the screen that the components were drawn on, which has 105 pixels to the inch
const USUAL_PX = 17.5

"""
How much bigger the theme's text is than the usual size, 12pt. A component
multiplies its lengths by this, so that its boxes still fit its text. With the
usual size a label is 13pt, so `Theme(size=24pt)` makes labels 26pt.

A theme can give its size in pixels, as an app does when its own sizes are all
in pixels. Then the usual size is 17.5px, which is what 12pt was on the screen
the components were drawn on. How many pixels a point is depends on the
screen, so a size in points would make the boxes of such an app bigger or
smaller against its text from one screen to the next.
"""
scale(t::Theme=theme()) = t.size isa px ? t.size.value / USUAL_PX : convert(pt, t.size).value / 12

"""
The size for text that is `size` when the theme's text is the usual 12pt:
`sized(13pt)` for a label. It's in the unit of the theme's own size, so in a
theme of pixels it's the same number of pixels on every screen. A `size` in
pixels is multiplied by `scale(t)`, like any other length in pixels.
"""
sized(size, t::Theme=theme()) = size isa px ? size * scale(t) : t.size * (convert(pt, size).value / 12)

@Enum WrapMode words newlines none

"""
Text that's made outside a `describe`, like the label of a tree's item, gets
the colour and the font of the default theme. This gives such text the colour
and font of `t`. Text that was given its own colour or font keeps it.
`was` is the theme the text has now.
"""
adopt_theme!(text, t::Theme=theme(), was::Theme=light) = begin
  text.color == was.text && (text.color = t.text)
  text.family == was.family && (text.family = t.family)
  text
end
@Enum TextAlign Left Center Right

@def mutable struct Text <: UITree
  content::String=""
  color::Colorant=THEME[].text
  size::Length=12pt
  family::String=THEME[].family
  subfamily::String=""
  lineheight::Length=1.5em
  weight::Int16=400               # 400 is regular and 700 is bold. `subfamily` wins when it's given.
  wrap::WrapMode=WrapMode.words
  align::TextAlign=TextAlign.Left
end

Text(content::String; kwargs...) = Text(;content=content, kwargs...)
Base.convert(::Type{UI}, s::AbstractString) = Text(s)

"Represents the UI as the user thinks of it"
@abstract struct SemanticUI <: UITree
  firstchild::Union{UI,Nothing}=nothing
  stale::Bool=true
  state::Any=nothing
  inherited_theme::Any=nothing   # the Theme it was last described with. Read it with `theme(node)`
  slot::Int=0                    # its place among the nodes its owner's `describe` makes, or 0 for a node in the tree
  kept::Any=nothing              # what its geometry remembers between frames, like how far a Scroll has scrolled
  memo::Any=nothing              # its last geometry, kept to use again while its `inputs` stay the same
end

"""
Return `handled` from an event handler to keep the event from the nodes above.
Without it, the event goes on to each semantic parent in turn:

    onkey(b::DeleteButton, ::KeyPress{Keys.mouse_left}) = (remove!(b.parent); handled)
"""
struct Handled end
const handled = Handled()

"Top-level node that connects the UI tree to a window"
@def mutable struct Root <: SemanticUI
  window::Any=nothing
end
Root(child::UITree; window=nothing) = begin
  root = Root(window=window)
  add_child!(root, child)
  # Components put straight into a layout, with no semantic node around them, belong to the root.
  # That's how they find their window.
  child isa GeometricUI && adopt_inline!(root, child)
  root
end

@property Text.firstchild = nothing
@property UITree.lastchild = lastsibling(self.firstchild)
@property UITree.children = SiblingIterator(self.firstchild)
# Enable lazy generation of children for semantic nodes
@property SemanticUI.firstchild = begin
  fc = getfield(self, :firstchild)
  isnothing(fc) || return fc
  adopt!(self, describe_children(self))
  getfield(self, :firstchild)
end

adopt!(parent::UITree, children::Nothing) = parent
adopt!(parent::UITree, children) = begin
  lastchild = nothing
  for child in children
    setfield!(child, :parent, parent)
    if isnothing(lastchild)
      setfield!(parent, :firstchild, child)
    else
      setfield!(lastchild, :nextsibling, child)
      setfield!(child, :prevsibling, lastchild)
    end
    lastchild = child
  end
  parent
end

# A node points at its parent and its children, so printing all of its fields prints the whole
# tree, many times over. That takes minutes for a small app. So a node prints as its kind and
# how many children it has, e.g. `Row with 3 children`.
Base.show(io::IO, node::UITree) = begin
  n = nsiblings(getfield(node, :firstchild))
  print(io, nameof(typeof(node)), n == 0 ? "" : n == 1 ? " with 1 child" : " with $n children")
end
Base.show(io::IO, text::Text) = print(io, "Text(", repr(text.content), ")")

"Define this method if you want to generate the children of a SemanticUI node lazily"
describe_children(ui) = nothing

"Represents the UI as a high level description of geometric shapes"
@abstract struct GeometricUI <: UITree
  firstchild::Union{UI,Nothing}=nothing
  from::Union{Nothing,UI}=nothing
end
Base.convert(::Type{GeometricUI}, node::GeometricUI) = node
Base.convert(::Type{GeometricUI}, node::SemanticUI) = begin
  own!(DESCRIBING[], node)
  geometry(node)
end

"The node whose `describe` is running, how many nodes that `describe` has made so far, and whether it asked to be drawn again soon"
mutable struct Describing
  node::SemanticUI
  made::Int
  timed::Bool
end
const DESCRIBING = Base.ScopedValues.ScopedValue{Union{Nothing,Describing}}(nothing)

# --- skipping what hasn't changed -------------------------------------------------

"""
What `describe(node)` reads. Define it for a kind of node, and `describe` only
runs for a node of that kind when one of these values has changed since the
last frame. Until then the node's geometry and its layout are used again.

    inputs(row::TodoRow) = (row.text, row.done)

Give every value that `describe` reads: the node's own fields, the fields of
other nodes, and anything outside the tree. Give values, not objects that
change in place. A `Vector` is fine, because it's compared by what's in it, but
a mutable struct is compared by which object it is. So give `item.done`, not `item`.

You don't have to give these. The library adds them itself:

- whether the mouse is over the node, and whether it has the keyboard
- the theme, and the size the window lays the app out at
- which children the node has. A child that changes is described again by
  itself, and its new geometry takes the place of its old in the parent's.

A `describe` that asks for another frame with `redraw_in!` is run again on that
frame whatever its inputs are. One that reads the time by itself has to give
the time as an input. A node without `inputs` is described on every frame, as
it always was.

If part of an app looks out of date, an input is missing. `skipping[] = false`
turns all of this off, to check.
"""
inputs(node) = nothing

"Set this to `false` to describe and lay out everything on every frame, whatever `inputs` say"
const skipping = Ref(true)

"What the window adds to a node's inputs. `draw.jl` defines it for a node in a window."
ambient(node) = UInt(0)

"A semantic node whose geometry is part of another node's geometry"
mutable struct Embedded
  geo::GeometricUI      # its geometry, where it sits in the other node's
  source::SemanticUI
  seen::Int             # the `version` its geometry had when the other node last looked
  theme::Theme          # the theme it was described with there
end

Base.show(io::IO, e::Embedded) = print(io, "Embedded(", e.source, ")")

"A node's last geometry, and what it takes to know whether that can be used again"
mutable struct Memo
  signature::UInt               # its inputs, as one number
  geometry::GeometricUI
  embedded::Vector{Embedded}    # the nodes whose geometry is in it
  version::Int                  # a new number each time anything in the geometry changes
  edited::Bool                  # the app changed the geometry in place since it was last looked at
  layout::Any                   # the rectangle the last layout made for the geometry
  laid::Int                     # the `version` that layout was of
end

Base.show(io::IO, memo::Memo) = print(io, "Memo(", memo.geometry, ", version ", memo.version, ")")

# Each change to a geometry takes the next number as its `version`
const changes = Ref(0)

# Each time something changes that a layout depends on but a geometry doesn't show, like a font
# registered under a name that's in use, this goes up and every kept layout is dropped
const epoch = Ref(0)

"A node's inputs as one number, or 0 for a node that's described on every frame"
signature(node::SemanticUI) = begin
  skipping[] || return UInt(0)
  mine = inputs(node)
  mine === nothing && return UInt(0)
  # The count of method definitions is in it, so that code loaded again while the app runs, as
  # `examples/hot_reload.jl` does, describes everything again and a change to a `describe` shows
  h = hash(mine, hash(Base.get_world_counter(), ambient(node)))
  child = getfield(node, :firstchild)
  while child !== nothing
    h = hash(objectid(child), h)
    child = getfield(child, :nextsibling)
  end
  h == 0 ? UInt(1) : h
end

"The `version` of a node's geometry, or 0 for a node that's described on every frame"
version(node::SemanticUI) = (memo = getfield(node, :memo); memo isa Memo ? memo.version : 0)

"The geometry of `node`: its last one if its inputs are what they were, or else what `describe` makes of it now"
function geometry(node::SemanticUI)
  now = THEME[]
  memo = getfield(node, :memo)
  key = signature(node)
  if memo isa Memo && key != 0 && memo.signature == key && getfield(node, :inherited_theme) === now
    refresh!(node, memo)
    return memo.geometry
  end
  setfield!(node, :inherited_theme, now)
  describing = Describing(node, 0, false)
  result = Base.ScopedValues.with(() -> describe(node), DESCRIBING => describing)
  # A `describe` that hands on another node's geometry can't be skipped: that node wouldn't be looked at
  borrowed = result.from isa SemanticUI && result.from !== node
  result.from = node
  keep = key != 0 && !describing.timed && !borrowed
  embedded = keep ? Embedded[] : nothing
  adopt_inline!(node, result, Ref(0), embedded)
  setfield!(node, :stale, true)
  setfield!(node, :memo, keep ? Memo(key, result, embedded, changes[] += 1, false, nothing, 0) : nothing)
  result
end

"""
A node's geometry is being used again. Look at each node whose geometry is in
it. One that has changed is described again, and its new geometry takes the
place of its old. `node.stale` says afterwards whether anything in the geometry
changed.
"""
function refresh!(node::SemanticUI, memo::Memo)
  changed = false
  for e in memo.embedded
    new = THEME[] === e.theme ? geometry(e.source) : with_theme(() -> geometry(e.source), e.theme)
    if new !== e.geo
      swap!(e.geo, new)
      e.geo = new
      changed = true
    end
    seen = version(e.source)
    seen == e.seen || (changed = true; e.seen = seen)
  end
  # Read last: describing a node above may change this one's geometry in place, as `reuse!` does
  changed |= memo.edited
  memo.edited = false
  if changed
    memo.version = changes[] += 1
    edits[] += 1
  end
  setfield!(node, :stale, changed)
  nothing
end

"Put `new` where `old` is in its parent"
swap!(old::GeometricUI, new::GeometricUI) = begin
  parent, prev, next = getfield(old, :parent), getfield(old, :prevsibling), getfield(old, :nextsibling)
  setfield!(new, :parent, parent)
  setfield!(new, :prevsibling, prev)
  setfield!(new, :nextsibling, next)
  prev === nothing ? setfield!(parent, :firstchild, new) : setfield!(prev, :nextsibling, new)
  next === nothing || setfield!(next, :prevsibling, new)
  setfield!(old, :parent, nothing)
  setfield!(old, :prevsibling, nothing)
  setfield!(old, :nextsibling, nothing)
  nothing
end

"Say that the `describe` that's running reads the time, so it has to run again on the next frame"
timed!() = (describing = DESCRIBING[]; describing === nothing || (describing.timed = true); nothing)

"The rectangle the last layout made for a node's geometry, or `nothing` if the geometry has changed since"
laid(node::SemanticUI) = (memo = getfield(node, :memo); memo isa Memo && memo.laid == memo.version ? memo.layout : nothing)

"Keep the rectangle a layout made for a node's geometry"
laid!(node::SemanticUI, rect) = begin
  memo = getfield(node, :memo)
  memo isa Memo && (memo.layout = rect; memo.laid = memo.version)
  nothing
end

"Tell the nodes whose kept geometry `node` is part of that the app has changed it in place"
touch!(node) = begin
  while node !== nothing
    if node isa GeometricUI
      source = getfield(node, :from)
      memo = source isa SemanticUI ? getfield(source, :memo) : nothing
      memo isa Memo && (memo.edited = true)
    end
    node = getfield(node, :parent)
  end
end

"""
A node that a `describe` makes, like the `Icon` in a button, is a new object on
each frame. This gives it to the node being described and numbers it, so that
this frame's `Icon` can be matched with the one from the frame before. See `same`.
"""
own!(::Nothing, node::SemanticUI) = nothing
own!(d::Describing, node::SemanticUI) = begin
  parent = getfield(node, :parent)
  if parent === nothing
    setfield!(node, :parent, d.node)
  elseif parent !== d.node || getfield(node, :slot) == 0
    return   # it's in the tree, so it's the same object on every frame
  end
  setfield!(node, :slot, d.made += 1)
  nothing
end

"""
True when `a` and `b` are one node. Two objects count as one node when the same
`describe` made each of them, at the same place, on different frames.
"""
same(a, b) = a === b
same(a::SemanticUI, b::SemanticUI) =
  a === b || (getfield(a, :slot) != 0 && getfield(a, :slot) == getfield(b, :slot) && typeof(a) === typeof(b) &&
              same(semantic_parent(a), semantic_parent(b)))

"The nearest semantic node above `node`"
semantic_parent(node) = begin
  node = getfield(node, :parent)
  while node !== nothing && !(node isa SemanticUI)
    node = getfield(node, :parent)
  end
  node
end

"""
Semantic nodes made inside a `describe`, like an `Icon` in a button, belong to
the node being described. Giving them that parent lets their clicks bubble up
to it, and makes `ishovered` true for it while the cursor is over them.
"""
adopt_inline!(owner::SemanticUI, geo::UITree, count=Ref(0), found=nothing) = begin
  remember!(owner, geo, count)
  for child in geo.children
    source = child isa GeometricUI ? getfield(child, :from) : nothing
    if source isa SemanticUI
      source !== owner && getfield(source, :parent) === nothing && setfield!(source, :parent, owner)
      # When the owner's geometry is kept, it has to know whose geometry is in it
      found === nothing || push!(found, Embedded(child, source, version(source), something(getfield(source, :inherited_theme), THEME[])))
    else
      adopt_inline!(owner, child, count, found)
    end
  end
end

"""
Geometry is made anew on each frame, so what a piece of it has to remember,
like how far a Scroll has scrolled, is kept by the semantic node whose
`describe` made it. `remember!` gives `geo` what was kept for it. `count` is how
many pieces of `owner`'s geometry have asked so far, which tells one from another.
"""
remember!(owner, geo, count) = nothing

"What `owner` keeps under `key` for its geometry. `make()` makes it the first time."
kept!(make, owner::SemanticUI, key) = begin
  store = getfield(owner, :kept)
  store === nothing && (store = setfield!(owner, :kept, Dict{Any,Any}()))
  get!(make, store::Dict{Any,Any}, key)
end

@def struct SiblingIterator
  node::Union{Nothing,UITree}
end

Base.iterate(i::SiblingIterator) = iterate(i, i.node)
Base.iterate(i::SiblingIterator, state::Nothing) = nothing
# `getfield`, because the kind of node isn't known here, and looking a property up by name is slow then
Base.iterate(i::SiblingIterator, state::UITree) = (state, getfield(state, :nextsibling))
Base.eltype(::SiblingIterator) = UI
Base.length(i::SiblingIterator) = nsiblings(i.node)
Base.lastindex(i::SiblingIterator) = length(i)
Base.getindex(i::SiblingIterator, n::Int) = begin
  n < 1 && throw(BoundsError(i, n))
  node = i.node
  for _ in 1:n-1
    isnothing(node) && throw(BoundsError(i, n))
    node = node.nextsibling
  end
  isnothing(node) && throw(BoundsError(i, n))
  node
end
Base.getindex(i::SiblingIterator, r::AbstractUnitRange{Int}) = begin
  first(r) < 1 && throw(BoundsError(i, r))
  node = i.node
  for _ in 1:first(r)-1
    isnothing(node) && throw(BoundsError(i, r))
    node = node.nextsibling
  end
  result = UI[]
  for _ in first(r):last(r)
    isnothing(node) && throw(BoundsError(i, r))
    push!(result, node)
    node = node.nextsibling
  end
  result
end
nsiblings(d::Nothing) = 0
nsiblings(d::UITree) = begin
  n = 0
  while d !== nothing
    n += 1
    d = getfield(d, :nextsibling)
  end
  n
end
lastsibling(d::UITree) = begin
  while (next = getfield(d, :nextsibling)) !== nothing
    d = next
  end
  d
end
lastsibling(d::Nothing) = nothing

mixin!(r::UITree, s::StyleNode) = begin
  field = propertyname(r, s)
  old = getproperty(r, field)
  setproperty!(r, field, mixin!(old, s))
  r   # so that `mixin!(node, a, b)` gives `b` to the node too, not to `a`
end
mixin!(r::UITree, d::UITree) = add_child!(r, d)
mixin!(r::GeometricUI, d::SemanticUI) =
  add_child!(r, convert(GeometricUI, d))
propertyname(s::StyleNode) = Symbol(snake_case(string(nameof(typeof(s)))))
propertyname(_, s) = propertyname(s)
snake_case(s::AbstractString) = NamingConventions.convert(NamingConventions.PascalCase, NamingConventions.SnakeCase, s)
add_child!(r::UITree, child::UITree) = begin
  # Geometry that's used again was in last frame's tree, and still points at what was beside it there
  if child isa GeometricUI
    setfield!(child, :prevsibling, nothing)
    setfield!(child, :nextsibling, nothing)
  end
  if isnothing(r.firstchild)
    r.firstchild = child
  else
    last = r.lastchild
    last.nextsibling = child
    child.prevsibling = last
  end
  child.parent = r
end
detach!(node::UITree) = begin
  parent = node.parent
  isnothing(parent) && return node
  prev = node.prevsibling
  next = node.nextsibling
  isnothing(prev) ? setfield!(parent, :firstchild, next) : (prev.nextsibling = next)
  isnothing(next) || (next.prevsibling = prev)
  node.parent = nothing
  node.prevsibling = nothing
  node.nextsibling = nothing
  node
end

"""
Put a stateful node, like a `Scroll`, into a freshly built tree. Geometry is
usually rebuilt every frame, but a Scroll keeps its offset on itself, so the
same instance has to come back each frame. This detaches it from last frame's
tree, swaps in the new children and returns it, ready to be added to a parent.
"""
reuse!(node::UITree, children...) = begin
  detach!(node)
  for child in collect(node.children)
    detach!(child)
  end
  for child in children
    mixin!(node, child)
  end
  node
end

# How many times a layout has been changed, anywhere. A window keeps the layout it resolved last, and
# uses it again while this count is what it was then. So a layout that an app keeps and changes in
# place, e.g. `row.height = height(20px)`, is resolved again without the app having to say so.
const edits = Ref(0)
Base.setproperty!(node::Union{GeometricUI,Text}, ::Field{name}, value) where name = begin
  edits[] += 1
  # A node with a parent may be part of geometry that's kept to use again. A change to where the
  # node is in the tree changes what its parent holds, not the node.
  parent = getfield(node, :parent)
  parent === nothing || touch!(name === :parent || name === :prevsibling || name === :nextsibling ? parent : node)
  setfield!(node, name, value)
end

"A symbolic representation of an image which just happens to be a UI"
@abstract struct ConcreteUI <: UITree
  from::Union{Nothing,UI}=nothing
end

"""
Converts a UI representation into a more specific one. Julia's dispatch routes by argument type:
  - `describe(data, key)` creates the semantic UI (SemanticUI) from data
  - `describe(::SemanticUI)` strips state to produce a visual description (GeometricUI)
  - `describe(::GeometricUI, size)` resolves layout into concrete positions (ConcreteUI)
"""
function describe end
describe(d::GeometricUI) = d

"Call describe(node) and set result.from = node, returning the GeometricUI"
describe!(node::SemanticUI) = convert(GeometricUI, node)

"""
Extracts the domain data currently represented by a UI node.
"""
function integrate end

"""
Used to notify the relevant semantic UI node of some user input. To respond to this input just
specialize this method on either the type of node or the type of event or both.
"""
function on(ui_node, event) end

"The top of the tree that `node` belongs to"
root_of(node::UITree) = begin
  root = node
  while (parent = getfield(root, :parent)) !== nothing
    root = parent
  end
  root
end

"The window showing `node`, or `nothing` if it isn't attached to one"
window_of(node::UITree) = begin
  root = root_of(node)
  root isa Root ? root.window : nothing
end

"""
Switches the target of future keyboard events to a given semantic node. The
node that had the keyboard is told with `onblur`.
"""
focus(node::UITree) = begin
  root = root_of(node)
  root isa Root || return node
  w = root.window
  old = w.focus
  w.focus = node
  old isa SemanticUI && old !== node && blur!(old)
  node
end

"""
`onblur(node, from)` runs when `from` loses the keyboard to another node. It runs
on `from` and then on each semantic node above it, until one returns `handled`.
A field that's edited in place can use it to stop editing:

    onblur(v::Value, from) = from === v.editor ? (v.editing = false; handled) : nothing

The keyboard has already gone to the other node, so a handler shouldn't call `focus`.
"""
onblur(node, from) = nothing

blur!(from) = begin
  node = from
  while node !== nothing
    onblur(node, from) === handled && return handled
    node = semantic_parent(node)
  end
  nothing
end
