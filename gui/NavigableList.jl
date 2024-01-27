@use "github.com/jkroso/Prospects.jl" @mutable Field
@use "github.com/jkroso/Sequences.jl" Cons EmptySequence
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom focus children
@use "../event.jl" onmousedown onkeydown ondblclick onfocusout onfocusin tick emit Change Submit
@use "./basic.jl" VStack chevron
@use "./Icon.jl" Icon

Cons(1)


@mutable struct NavigableList <: Component
  interest::Path{Int}=Cons(1)
end

onkeydown(ui::NavigableList, event) = begin
  if event.key == "ArrowDown"
    ui.interest = min(ui.interest + 1, length(ui.children))
  elseif event.key == "ArrowUp"
    ui.interest = max(ui.interest - 1, 1)
  elseif event.key == "ArrowRight"
    interest = ui.children[ui.interest]
    interest.collapsed = false
  elseif event.key == "ArrowLeft"
    ui.children[ui.interest].collapsed = true
  end
  for c in ui.children
    c.stale = true
  end
end

@mutable Item <: Component
@mutable struct ItemGroup <: Component
  collapsed::Bool=true
  interest::Int=1
end

dom(ui::NavigableList) = begin
  children = map(c->convert(Node, c), ui.children)
  push!(children[ui.interest].attrs[:class], :interested)
  @dom[:div css"""
            display: flex
            flex-direction: column
            border: 1px solid #181a1f
            border-radius: 0.3rem
            overflow: scroll
            background: #2a2d35
            &.hasgroups > .item { padding-left: 2.2rem }
            """
            class.hasgroups = any(x->x isa ItemGroup, ui.children)
    children...]
end

dom(ui::Item) = begin
  @dom[:div css"""
            &:not(:last-child) { border-bottom: 1px solid #181a1f }
            background: #2a2d35
            padding: 0.75rem
            transition: background 0.2s
            &.interested { background: #3b3f4b }
            """
            class="item"
    ui.children...]
end

dom(ui::ItemGroup) = begin
  collapsed = ui.collapsed
  children = map(x->convert(Node,x), ui.children[2:end])
  push!(children[ui.interest].attrs[:class], :interested)
  @dom[:div css"""
            display: flex
            flex-direction: column
            padding: 0.75rem
            background: #2a2d35
            &:not(:last-child)
              border-bottom: 1px solid #181a1f
            &:not(:last-child) .leaves
              border-left: 1px solid #181a1f
            &.interested { background: #3b3f4b }
            """
    [:div css"display: flex; align-items: center" chevron(!collapsed) ui.firstchild]
    [:div css"margin-left: 0.1rem; padding-left: 1rem" class="leaves"
      (collapsed ? [] : children)...]]
end

@ui[NavigableList
  [Item "AUD"]
  [Item "NZD"]
  [Item "USD"]]

@ui[NavigableList
  [ItemGroup "A"
    [Item "B"]
    [Item "C"]]
  [ItemGroup "D"
    [Item "E"]]]
