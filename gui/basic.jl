@use "github.com/jkroso/Units.jl" mm ["Typography" pt]
@use "github.com/jkroso/Prospects.jl" @mutable @abstract interleave Field assoc
@use "github.com/jkroso/Promises.jl" @defer
@use "github.com/jkroso/Sequences.jl" push
@use "github.com/jkroso/DOM.jl" => DOM @dom @css_str empty_set
@use "../types.jl" Component UINode dom @ui children tree
@use "../style.jl" @style_str toclass!
@use "../selector.jl" identitykey
@use "../event.jl" onmousedown left
@use "./Icon.jl" Icon

"""
Takes some data and generates a user interface for viewing and manipulating it
"""
function gui(x)
  gui(x, identitykey)
end

dom_attrs(ui::UINode) = begin
  isnothing(ui.style) && return ui.attrs
  classes = get(ui.attrs, :class, empty_set)
  assoc(ui.attrs, :class, push(classes, toclass!(ui.style)))
end

@mutable HStack <: Component
dom(hs::HStack) = hstack(dom_attrs(hs), hs.children)
hstack(attrs, children) = @dom[:div{attrs...} css"display: inline-flex; flex-direction: row; align-items: center" children...]

@mutable VStack <: Component
dom(vs::VStack) = vstack(dom_attrs(vs), vs.children)
vstack(attrs, children) = @dom[:div{attrs...} css"display: flex; flex-direction: column" children...]

@mutable Heading(level::UInt8) <: Component
dom(ui::Heading) = begin
  h = DOM.Container{Symbol('h', ui.level)}
  @dom[h ui.children...]
end

@mutable Chevron(isopen=false) <: Component
dom(ui::Chevron) = chevron(ui.isopen)
chevron(isopen) = @dom[:span style.transform=isopen ? "rotate(0.25turn)" : "rotate(0turn)"
                             css"""
                             margin-right: 4px
                             transition: transform 0.1s ease-out
                             """
                             dom(Icon(name="chevron-right"))]

@mutable Expansion <: Component
children(ui::Expansion) = UINode[expansion(ui.data)]
dom(ui::Expansion) = begin
  children = ui.parent.isopen ? ui.children : UINode[]
  @dom[:div css"display: contents" children...]
end

"""
Generate a long form UI for a given object
"""
function expansion end

@abstract struct Expandable <: Component end
Base.getproperty(ui::Expandable, ::Field{:isopen}) = ui.firstchild.firstchild.isopen
Base.setproperty!(ui::Expandable, ::Field{:isopen}, x) = ui.firstchild.firstchild.isopen = x

dom(ui::Expandable) = @dom[vstack ui.children...]

children(ui::Expandable) = begin
  UINode[
    @ui[HStack [Chevron] [DataSummary]],
    @ui[Expansion]]
end

@mutable DataSummary <: Component
dom(ui::DataSummary) = brief(ui.data)

brief(m::Module) = @dom[:span class="syntax--keyword syntax--other" replace(repr(m), r"^Main\."=>"")]
"A summary of a datastructure"
brief(data::Union{AbstractDict,AbstractVector,Set}) =
  @dom[:span brief(typeof(data)) [:span css"color: rgb(104, 110, 122)" "[$(length(data))]"]]

brief(u::Union) = @dom[:span
  [:span class="syntax--support syntax--type" "Union"]
  [:span "{"]
  interleave(map(brief, union_params(u)), ",")...
  [:span "}"]]

union_params(u::Union) = push!(union_params(u.b), u.a)
union_params(u) = Any[u]
flatten_unionall(x::DataType, vars=[]) = x, vars
flatten_unionall(x::UnionAll, vars=[]) = flatten_unionall(x.body, push!(vars, x.var))
brief(data::T) where T = @dom[:span brief(T) '[' length(propertynames(data)) ']']
brief(n::Union{Number,Char}) = syntax(n)
brief(e::Enum) = doodle(e)
brief(x::UnionAll) = begin
  body, = flatten_unionall(x)
  @dom[:span
    [:span class="syntax--support syntax--type" body.name.name]
    [:span "{" interleave(map(brief_param, body.parameters), ",")... "}"]]
end
brief_param(t::TypeVar) = @dom[:span class="syntax--keyword syntax--operator syntax--relation syntax--julia" "<:" brief(t.ub)]
brief_param(x) = brief(x)

brief(T::DataType) = begin
  @dom[:span
    [:span class="syntax--support syntax--type" T.name.name]
    if !isempty(T.parameters)
      @dom[:span css"display: inline-flex; flex-direction: row"
        [:span "{"] interleave(map(brief, T.parameters), ",")... [:span "}"]]
    end]
end
brief(t::TypeVar) = @dom[:span t.name]
brief(s::Symbol) = doodle(s)
brief(f::StackTraces.StackFrame) = begin
  f.linfo isa Nothing && return @dom[:span string(f.func)]
  f.linfo isa Core.CodeInfo && return @dom[:span repr(f.linfo.code[1])]
  @dom[:span replace(sprint(Base.show_tuple_as_call, f.linfo.def.name, f.linfo.specTypes),
                     r"^([^(]+)\(.*\)$"=>s"\1")]
end
brief(m::Base.MethodList) = @dom[:span name(m) " has $(length(collect(m))) methods"]

onmousedown(ui::Expandable, event) = begin
  event.button == left || return
  event.target in ui.firstchild && toggle(ui)
end

expand(ui::UINode) = nothing
expand(ui::Expandable) = ui.isopen || toggle(ui)
toggle(ui::Expandable) = begin
  ui.isopen = !ui.isopen
  ui.children[2].stale = true
end

# @ui[VStack style"padding[left,right]: 5mm; border: 0.5mm solid; padding[top,bottom]: 20mm" [HStack "a"] [HStack "b"] [HStack "c"]]
