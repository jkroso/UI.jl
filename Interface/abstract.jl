@use "github.com/jkroso/Prospects.jl" @abstract @def @property Field group assoc ["Enum" @Enum]
@use "github.com/jkroso/Sequences.jl" ["collections/Map" Map]
@use "github.com/jkroso/Font.jl" Font ["units" pt px inch em]
@use "github.com/jkroso/Units.jl" Length mm cm m
@use Colors: Color, Colorant, RGB, hex
@use NamingConventions

const black = parse(Colorant, "black")

abstract type StyleNode end

@abstract struct UI end
@abstract struct UITree <: UI
  parent::Union{Nothing,UITree}=nothing
  prevsibling::Union{Nothing,UITree}=nothing
  nextsibling::Union{Nothing,UITree}=nothing
end

@Enum WrapMode words newlines none

@def mutable struct Text <: UITree
  content::String=""
  color::Colorant=black
  size::Length=12pt
  family::String="Helvetica"
  subfamily::String=""
  lineheight::Length=1.5em
  weight::Int16=600
  wrap::WrapMode=WrapMode.words
end

Text(content::String; kwargs...) = Text(;content=content, kwargs...)
Base.convert(::Type{UI}, s::AbstractString) = Text(s)

"Represents the UI as the user thinks of it"
@abstract struct SemanticUI <: UITree
  firstchild::Union{UI,Nothing}=nothing
  stale::Bool=true
  state::Any=nothing
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

"Represents the UI as a high level description of geometric shapes"
@abstract struct GeometricUI <: UITree
  firstchild::Union{UI,Nothing}=nothing
  from::Union{Nothing,UI}=nothing
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
mixin!(old, new) = new
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

function (::Type{T})(attrs...) where T <: UITree
  out = T()
  for s in attrs
    mixin!(out, s)
  end
  out
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
describe!(node::SemanticUI) = begin
  result = describe(node)
  result.from = node
  result
end

"""
Used to notify the relevant semantic UI node of some user input. To respond to this input just
specialize this method on either the type of node or the type of event or both.
"""
function on(ui_node, event) end

"""
Switches the target of future keyboard events to a given semantic node
"""
focus(node::UITree) = begin
  root = node
  while root.parent !== nothing
    root = root.parent
  end
  root isa Root && (root.window.focus = node)
  node
end
