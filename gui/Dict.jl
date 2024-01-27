@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom
@use "../event.jl" onmousedown
@use "./basic.jl" VStack

@mutable DictUI() <: Component

children(ui::DictUI) = begin
  UINode[
    @ui[HStack [Chevron] [DataSummary]],
    @defer @ui[VStack
      map(i->Pair(key=Iteration(i)), 1:length(ui.data))...
      [Button "+"]]]
end

@mutable DataSummary <: Component
dom(ds::DataSummary) = brief(ds.data)

Dict(:a=>1)
