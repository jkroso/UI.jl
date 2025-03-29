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
@abstract struct ConceptualUI <: UITree
  firstchild::Union{UI,Nothing}=nothing
  stale::Bool=true
  state::Any=nothing
end

@property Text.firstchild = nothing
@property UITree.lastchild = lastsibling(self.firstchild)
@property UITree.children = SiblingIterator(self.firstchild)

"Represents the UI as a high level description of geometric shapes"
@abstract struct DescriptiveUI <: UITree
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
nsiblings(d::Nothing) = 0
nsiblings(d::UITree) = nsiblings(d.nextsibling) + 1
lastsibling(d::UITree) = isnothing(d.nextsibling) ? d : lastsibling(d.nextsibling)
lastsibling(d::Nothing) = nothing

mixin!(r::UITree, s::StyleNode) = setproperty!(r, propertyname(r, s), s)
mixin!(r::UITree, d::UITree) = add_child!(r, d)
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
Create the semantic structure of the UI based on some input data and the conceptual context it's
being rendered in
"""
function gui end

"""
Converts a Conceptual UI Node into an abstract representation of just its visual aspects. At this
point we are essentially stripping state from the UI so that we can enjoy way more code reuse
"""
function describe end

"""
Converts a declarative UI into a concrete one. At this point we are calculating the layout based
on the actual screen size and with a known set of constraints
"""
function resolve end

"""
Used to notify the relevant semantic UI node of some user input. To respond to this input just
specialize this method on either the type of node or the type of event or both.
"""
function on(ui_node, event) end

"""
Switches the target of future keyboard events to a given semantic node. Will trigger a focus out
event on the old target and a focus in event on the new target.
"""
function focus end
