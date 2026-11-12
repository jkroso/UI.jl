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
    node = node.parent
  end
  THEME[]
end

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
  weight::Int16=600
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
end

"Top-level node that connects the UI tree to a window"
@def mutable struct Root <: SemanticUI
  window::Any=nothing
end
Root(child::UITree; window=nothing) = begin
  root = Root(window=window)
  add_child!(root, child)
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

"Define this method if you want to generate the children of a SemanticUI node lazily"
describe_children(ui) = nothing

"Represents the UI as a high level description of geometric shapes"
@abstract struct GeometricUI <: UITree
  firstchild::Union{UI,Nothing}=nothing
  from::Union{Nothing,UI}=nothing
end
Base.convert(::Type{GeometricUI}, node::GeometricUI) = node
Base.convert(::Type{GeometricUI}, node::SemanticUI) = begin
  setfield!(node, :inherited_theme, THEME[])
  result = describe(node)
  result.from = node
  adopt_inline!(node, result)
  result
end

"""
Semantic nodes made inside a `describe`, like an `Icon` in a button, belong to
the node being described. Giving them that parent lets their clicks bubble up
to it, and makes `ishovered` true for it while the cursor is over them.
"""
adopt_inline!(owner::SemanticUI, geo::UITree) = begin
  for child in geo.children
    source = child isa GeometricUI ? child.from : nothing
    if source isa SemanticUI
      source !== owner && source.parent === nothing && setfield!(source, :parent, owner)
    else
      adopt_inline!(owner, child)
    end
  end
end

@def struct SiblingIterator
  node::Union{Nothing,UITree}
end

Base.iterate(i::SiblingIterator) = iterate(i, i.node)
Base.iterate(i::SiblingIterator, state::Nothing) = nothing
Base.iterate(i::SiblingIterator, state::UITree) = (state, state.nextsibling)
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
nsiblings(d::UITree) = nsiblings(d.nextsibling) + 1
lastsibling(d::UITree) = isnothing(d.nextsibling) ? d : lastsibling(d.nextsibling)
lastsibling(d::Nothing) = nothing

mixin!(r::UITree, s::StyleNode) = begin
  field = propertyname(r, s)
  old = getproperty(r, field)
  setproperty!(r, field, mixin!(old, s))
end
mixin!(r::UITree, d::UITree) = add_child!(r, d)
mixin!(r::GeometricUI, d::SemanticUI) =
  add_child!(r, convert(GeometricUI, d))
propertyname(s::StyleNode) = Symbol(snake_case(string(nameof(typeof(s)))))
propertyname(_, s) = propertyname(s)
snake_case(s::AbstractString) = NamingConventions.convert(NamingConventions.PascalCase, NamingConventions.SnakeCase, s)
add_child!(r::UITree, child::UITree) = begin
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
  while root.parent !== nothing
    root = root.parent
  end
  root
end

"The window showing `node`, or `nothing` if it isn't attached to one"
window_of(node::UITree) = begin
  root = root_of(node)
  root isa Root ? root.window : nothing
end

"""
Switches the target of future keyboard events to a given semantic node
"""
focus(node::UITree) = begin
  root = root_of(node)
  root isa Root && (root.window.focus = node)
  node
end
