@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/Promises.jl" @defer
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom children
@use "../event.jl" onmousedown
@use "./basic.jl" VStack vstack dom_attrs Chevron HStack
@use "./Button.jl" Button
@use "./Pair.jl" PairUI
@use "../Selector.jl" get

@mutable DictUI() <: Component

struct IterationKey
  value::Any
end

get(d::Dict, k::IterationKey) = begin
  collect(d)[k.value]
end

children(ui::DictUI) = begin
  UINode[
    @ui[HStack [Chevron] [DataSummary]],
    @ui[VStack
      map(i->PairUI(key=IterationKey(i)), 1:length(ui.data))...
      [Button "+"]]]
end

@mutable DataSummary <: Component

dom(ds::DataSummary) = @dom[:div "data"]

dom(ui::DictUI) = begin
  @dom[:div css"display: flex; flex-direction: column; padding: 0.5em"
    ui.children...]
end

# @use "." gui
Dict(:a=>1)
