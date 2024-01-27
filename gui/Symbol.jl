@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom
@use "../event.jl" onmousedown
@use "./basic.jl" VStack

@mutable SymbolUI(colon=true) <: Component

dom(ui::SymbolUI) = begin
  str = ui.colon ? repr(ui.data) : string(ui.data)
  @dom[:span class="syntax--other syntax--symbol syntax--constant" str]
end
