@use "github.com/jkroso/Prospects.jl" @mutable @abstract @struct Field group assoc
@use "github.com/jkroso/Sequences.jl/collections/Map.jl" Map
@use "./style.jl" @style_str parse_style Style
@use "./selector.jl" identitykey get set
@use MacroTools: @capture, @match

@abstract struct UINode
  parent::Union{Nothing, UINode}=nothing
  prevsibling::Union{Nothing, UINode}=nothing
  nextsibling::Union{Nothing, UINode}=nothing
  key::Any=identitykey
  stale::Bool=true
  style::Union{Nothing, Style}=nothing
end

@mutable TextNode(value::AbstractString="") <: UINode
Base.convert(::Type{UINode}, str::AbstractString) = TextNode(str)

const empty_attrs = Map{Symbol,Any}()

"A component is a UINode which generates it's children lazily"
@abstract struct Component <: UINode
  attrs::AbstractDict{Symbol,Any}=empty_attrs
  firstchild::Union{Nothing, UINode}=nothing
end

"A subcomponent is just a component that depends upon variables from one of it's parents"
@abstract struct SubComponent <: Component end
Base.getproperty(c::SubComponent, sym::Field{:stale}) = c.parent.stale

Base.getproperty(c::UINode, sym::Symbol) = getproperty(c, Field{sym}())
Base.setproperty!(c::UINode, sym::Symbol, x) = setproperty!(c, Field{sym}(), x)
Base.setproperty!(c::UINode, sym::Symbol, x) = begin
  setproperty!(c, Field{sym}(), x)
  set_stale(c)
  x
end

Base.setproperty!(c::UINode, sym::Field{:stale}, x::Bool) = begin
  x ? set_stale(c) : setfield!(c, :stale, false)
  x
end

set_stale(c::Nothing) = nothing
set_stale(c::UINode) = begin
  getfield(c, :stale) && return nothing
  setfield!(c, :stale, true)
  set_stale(c.parent)
end

Base.getproperty(ui::UINode, f::Field{:firstchild}) = nothing
Base.getproperty(ui::UINode, f::Field{:children}) = ChildNodes(ui.firstchild)
Base.getproperty(c::Component, sym::Field{:firstchild}) = begin
  isnothing(getfield(c, :firstchild)) && tree(c, children(c)...)
  getfield(c, :firstchild)
end
Base.getproperty(ui::UINode, f::Field{:index}) = siblings_l(ui)+1

"""
Components can generate their children lazily if desired. If when a component has it's `children`
property accesses it has none then `children()` will be called on it and the array of values returned
will be assigned as it's children. This enables cyclical structures to be rendered without creating
an infinite loop
"""
children(c::Component) = ()

abstract type Children end
Base.eltype(c::Children) = UINode
Base.getindex(c::Children, r::UnitRange) = ChildSlice(c[r.start], r.stop - (r.start-1))

@struct ChildNodes(node::Union{UINode,Nothing}) <: Children
Base.iterate(c::ChildNodes) = iterate(c, (c.node))
Base.iterate(c::ChildNodes, next) = isnothing(next) ? nothing : (next, next.nextsibling)
Base.lastindex(c::ChildNodes) = 1+siblings_r(c.node)
Base.getindex(c::ChildNodes, i::Integer) = begin
  node = c.node
  isnothing(node) && throw(BoundsError())
  while i > 1
    node = node.nextsibling
    isnothing(node) && throw(BoundsError())
    i -= 1
  end
  node
end
Base.length(c::ChildNodes) = 1+siblings_r(c.node)

@struct ChildSlice(node::Union{UINode,Nothing}, len::Integer=siblings_r(node)) <: Children
Base.iterate(c::ChildSlice) = iterate(c, (c.node, c.len))
Base.iterate(c::ChildSlice, (node, len)) = len < 1 ? nothing : (node, (node.nextsibling, len-1))
Base.length(c::ChildSlice) = c.len
Base.lastindex(c::ChildSlice) = c.len
Base.getindex(c::ChildSlice, i::Integer) = begin
  0 < i <= length(c) || throw(BoundsError())
  node = c.node
  while i > 1
    node = node.nextsibling
    i -= 1
  end
  node
end
siblings_r(::Nothing) = 0
siblings_r(ui::UINode) = isnothing(ui.nextsibling) ? 0 : siblings_r(ui.nextsibling)+1
siblings_l(::Nothing) = 0
siblings_l(ui::UINode) = isnothing(ui.prevsibling) ? 0 : siblings_l(ui.prevsibling)+1
siblings(ui::UINode) = siblings_l(ui.prevsibling) + siblings_r(ui.nextsibling)

Base.in(needle::UINode, haystack::UINode) = any(child -> child == needle || needle in child, haystack.children)

Base.getproperty(c::Component, ::Field{:data}) = get(c.parent.data, c.key)
Base.setproperty!(c::Component, ::Field{:data}, x) = begin
  c.parent.data = set(c.parent.data, c.key, x)
end

macro ui(expr) ui_macro(expr) end
ui_macro(x::Any) = esc(x)
ui_macro(expr::String) = :(TextNode($expr))
ui_macro(expr::Expr) = begin
  if expr.head in (:hcat, :vcat, :array, :vect)
    args = expr.args
    if Meta.isexpr(args[1], :row)
      args = [args[1].args..., args[2:end]...]
    end
    this = tocall(args[1])
    attrs, children = group(isattr, @view args[2:end])
    style, children = group(isstyle, children)
    isempty(attrs) || push!(this.args, attr_expression(attrs))
    isempty(style) || push!(this.args, style_expression(style))
    :(tree($this, $(map(ui_macro, children)...)))
  else
    esc(expr)
  end
end
normalize_attr(e) = begin
  @match e begin
    (a_.b_ = c_) => :($(QuoteNode(a)) => $(QuoteNode(b)) => $(esc(c)))
    ((:a_|a_) = b_) => :($(QuoteNode(a)) => $(esc(b)))
    (s_Symbol) => :($(QuoteNode(s)) => $(esc(s)))
    _ => esc(e)
  end
end

Attrs(attrs::Pair...) = reduce(add_attr, attrs, init=empty_attrs)

tocall(s::Symbol) = Expr(:call, esc(s))
tocall(s::Expr) = begin
  @assert Meta.isexpr(s, :call) repr(s)
  args = s.args[2:end]
  Expr(:call, esc(s.args[1]), map(esc, args)...)
end
isattr(e) = @capture(e, (_ = _))
isstyle(e) = @capture(e, @style_str(_))
add_attr(d::AbstractDict, (key,value)::Pair{Symbol,<:Pair}) = begin
  assoc(d, key, assoc(get(d, key, empty_attrs), value[1], value[2]))
end
add_attr(d::AbstractDict, (key,value)::Pair) = assoc(d, key, value)
attr_expression(attrs) = Expr(:kw, :attrs, :(Attrs($(map(normalize_attr, attrs)...))))
style_expression(styles) = begin
  Expr(:kw, :style, parse_style(styles[1].args[3]))
end

tree(parent, children...) = begin
  foldl(children, init=nothing) do prev_sibling, child
    isnothing(child) && return prev_sibling
    add_child!(parent, adopt(parent, child), prev_sibling)
  end
  parent
end

"""
Gives you a chance to wrap/modify child nodes before they become children of a Component type

```julia
@ui[ButtonGroup "a" "b" "c"]
```

In this case the user doesn't need to bother wrapping each TextNode in a Button
"""
adopt(parent, child) = convert(UINode, child)

add_child!(parent::UINode, child::UINode, prevsibling=last_child(parent)) = begin
  setfield!(child, :parent, parent)
  if isnothing(prevsibling)
    setfield!(parent, :firstchild, child)
  else
    setfield!(prevsibling, :nextsibling, child)
    setfield!(child, :prevsibling, prevsibling)
  end
  child
end

last_child(ui::UINode) = isnothing(ui.firstchild) ? nothing : last_sibling(ui.firstchild)
last_sibling(ui::UINode) = isnothing(ui.nextsibling) ? ui : last_sibling(ui.nextsibling)

"Generate an HTML DOM representation of the UINode"
function dom end

"Sets the target of keyboard events"
function focus end

"Unsets the target of keyboard events"
function blur end

init(ui::UINode) = foreach(init, ui.children)
onmount(ui::UINode) = nothing
ondismount(ui::UINode) = nothing
