@use "github.com/jkroso/Sequences.jl" Sequence EmptySequence Cons rest prepend
@use "github.com/jkroso/Prospects.jl" @abstract @mutable
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom focus children onmount
@use "../event.jl" onkeydown @key_str
@use "./basic.jl" chevron

@mutable struct ListTree <: Component
  interest::Cons{Int}=convert(Cons{Int}, (1,))
end

getchild(ui, path::Sequence) = getchild(ui.children[first(path)], rest(path))
getchild(ui, path::EmptySequence) = ui

onmount(ui::ListTree) = begin
  c = getchild(ui, ui.interest)
  c ≡ ui && return
  c.interested = true
end

transfer_interest(from, to::Nothing) = nothing
transfer_interest(from, to) = begin
  nav = get_navigator(to)
  nav.interest = path_to(to, nav)
  from.interested = false
  to.interested = true
end

get_navigator(x::ListTree) = x
get_navigator(x) = get_navigator(x.parent)

path_to(bottom, top) = begin
  path = convert(Cons{Int}, ())
  while bottom !== top
    path = prepend(path, bottom.index)
    bottom = bottom.parent
  end
  path
end

@abstract struct TreeItem <: Component
  interested::Bool=false
  selected::Bool=false
end

@mutable Item <: TreeItem
@mutable struct ItemGroup <: TreeItem
  collapsed::Bool=true
end

dom(ui::ListTree) = begin
  @dom[:div css"""
            display: flex
            flex-direction: column
            border: 1px solid #181a1f
            border-radius: 0.3rem
            overflow: scroll
            background: rgb(32,34,40)
            padding: 0.3rem 0.6rem 0.4rem 0.6rem
            """
    ui.children...]
end

const blank_indent = @dom[:indent css"width: 2rem; height: 4rem"]
const zero_width_indent = @dom[:indent css"width: 0rem; height: 4rem"]
const through_indent = @dom[:indent css"""
                                 width: 2rem
                                 height: 4rem
                                 display: flex
                                 flex-direction: row
                                 align-items: flex-start
                                 justify-content: flex-end
                                 &:after
                                   border-left: 2px solid rgb(49,52,58)
                                   box-sizing: content-box
                                   content: ''
                                   height: 100%
                                   width: 50%
                                 """]
const through_connect = @dom[:indent css"""
                             width: 2rem
                             height: 4rem
                             display: flex
                             flex-direction: row
                             align-items: center
                             justify-content: center
                             > div {flex-grow: 1}
                             """
  [:div css"border-right: 1px solid rgb(49,52,58); height: 100%"]
  [:div css"border-left: 1px solid rgb(49,52,58); height: 100%; display: flex; flex-direction: column; justify-content: center"
    [:div css"border: 1px solid rgb(49,52,58)"]]]

const end_connect = @dom[:indent css"""
                                 width: 2rem
                                 height: 4rem
                                 display: flex
                                 flex-direction: row
                                 align-items: flex-start
                                 justify-content: flex-end
                                 &:after
                                   border-left: 2px solid rgb(49,52,58)
                                   border-bottom: 2px solid rgb(49,52,58)
                                   border-bottom-left-radius: 0.5rem
                                   box-sizing: content-box
                                   content: ''
                                   height: 50%
                                   width: 50%
                                 """]

islast(ui) = ui.nextsibling == nothing
depth(ui::TreeItem) = ui.parent isa ListTree ? 0 : 1 + depth(ui.parent)
rems(ui::Item) = 4
rems(ui::ItemGroup) = 4 + (ui.collapsed ? 0 : sum(rems, ui.children[2:end]))

indents(ui) = begin
  p = convert(Cons{Node}, ())
  ui.parent isa ListTree && return prepend(p, zero_width_indent)
  p = prepend(p, islast(ui) ? end_connect : through_connect)
  ui = ui.parent
  while !(ui.parent isa ListTree)
    p = prepend(p, islast(ui) ? blank_indent : through_indent)
    ui = ui.parent
  end
  p
end

const header_css = css"""
display: flex
&.interested > header > content{ background: #3b3f4b }
> header
  display: flex
  align-items: center
  flex-grow: 1
  height: 4rem
> header > content
  display: flex
  align-items: center
  transition: background 0.2s
  background: rgb(49,52,58)
  border-radius: 0.3rem
  padding: 0.75rem
  flex-grow: 1
"""

dom(ui::Item) = begin
  @dom[:div css"align-items: center"
            class=header_css
            class.interested=ui.interested
            class.selected=ui.selected
    [:header indents(ui)... [:content ui.firstchild]]]
end

dom(ui::ItemGroup) = begin
  @dom[:div css"""
            flex-direction: column
            position: relative
            > spacer
              position: absolute
              top: 3.8rem
            > spacer > div
              border-right: 2px solid rgb(49,52,58)
              height: 0.3rem
            &.collapsed > spacer { opacity: 0 }
            > leaves
              display: flex
              flex-direction: column
              transition: height 170ms
              overflow: hidden
            """
            class=header_css
            class.interested=ui.interested
            class.selected=ui.selected
            class.collapsed=ui.collapsed
    [:header indents(ui)... [:content chevron(!ui.collapsed) ui.firstchild]]
    [:spacer [:div style.width="$(depth(ui)*2+1)rem"]]
    [:leaves style.height="$(ui.collapsed ? 0 : sum(rems, ui.children[2:end]))rem" ui.children[2:end]...]]
end

nextfamily(ui) = begin
  ui.parent isa ListTree && return ui.nextsibling
  while ui.parent.nextsibling == nothing
    ui = ui.parent
    ui.parent isa ListTree && return nothing
  end
  ui.parent.nextsibling
end

lastopen(ui::ItemGroup) = ui.collapsed ? ui : lastopen(ui.children[end])
lastopen(ui::Item) = ui

onkeydown(ui::ListTree, ::key"ArrowDown") = begin
  child = getchild(ui, ui.interest)
  if isnothing(child.nextsibling)
    if child isa ItemGroup && !child.collapsed
      transfer_interest(child, child.children[2])
    else
      transfer_interest(child, nextfamily(child))
    end
  elseif child isa ItemGroup && !child.collapsed
    transfer_interest(child, child.children[2])
  else
    transfer_interest(child, child.nextsibling)
  end
end

onkeydown(ui::ListTree, ::key"ArrowUp") = begin
  child = getchild(ui, ui.interest)
  cutoff = child.parent isa ListTree ? 1 : 2
  if child.index > cutoff
    transfer_interest(child, lastopen(child.prevsibling))
  elseif !(child.parent isa ListTree)
    transfer_interest(child, child.parent)
  end
end

onkeydown(ui::ListTree, ::key"ArrowRight") = begin
  child = getchild(ui, ui.interest)
  child isa ItemGroup || return
  if child.collapsed
    child.collapsed = false
  else
    transfer_interest(child, child.children[2])
  end
end

onkeydown(ui::ListTree, ::key"ArrowLeft") = begin
  child = getchild(ui, ui.interest)
  if child isa ItemGroup && !child.collapsed
    child.collapsed = true
  else
    child.parent isa ListTree && return nothing
    transfer_interest(child, child.parent)
  end
end

# @use "./basic.jl" HStack @style_str
#
# @ui[ListTree
#   [ItemGroup(collapsed=false) "Openwheel"
#     [ItemGroup(collapsed=false) "Formula 1"
#       [ItemGroup(collapsed=false) "Formula 2"
#         [Item "Formula 3"]
#         [Item "Formula Renault"]
#         [Item "Formula Ford"]]]
#     [ItemGroup "Indycar"
#       [Item "Cart"]]]
#   [ItemGroup "Stockcar"
#     [ItemGroup "Nascar"
#       [Item "Xfinity"]
#       [Item "Trucks"]]
#     [ItemGroup "Supercars"
#       [ItemGroup "Super 2"
#         [Item "Super 3"]]]]]
