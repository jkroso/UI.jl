@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom children
@use "../event.jl" onmousedown
@use "./basic.jl" VStack describe

@mutable PairUI <: Component
children(c::PairUI) = begin
  UINode[describe(x, i) for (i,x) in enumerate(c.data)]
end

dom(ui::PairUI) = begin
  @dom[:span convert(Node, ui.firstchild)
             [:span css"padding: 0 0.5rem" class="syntax--keyword" "=>"]
             convert(Node, ui.children[2])]
end

# :a => 1
