@use "github.com/jkroso/Prospects.jl" @mutable @abstract @field_str field_map
@use "github.com/jkroso/DOM.jl" @css_str @dom Map
@use "../types.jl" Component dom onmount

@abstract struct AbstractSatellite <: Component
  bounds::Vector=fill((x=0, y=0, width=0.0, height=0.0), 2)
  show::Bool=false
  placement::Symbol=:bottom
  gap::Any="2px"
end

onmount(ui::AbstractSatellite) = begin
  ui.bounds = map(field"dimensions", ui.children)
end

position((;bounds,placement,gap)::AbstractSatellite) = begin
  target,object = bounds
  if placement == :bottom
    Map(:top=>"calc(100% + $gap)",
        :left=>"$(target.width/2 - object.width/2)px")
  elseif placement == :right
    Map(:top=>"$(target.height/2 - object.height/2)px",
        :left=>"calc(100% + $gap)")
  elseif placement == :left
    Map(:top=>"$(target.height/2 - object.height/2)px",
        :right=>"calc(100% + $gap)")
  elseif placement == :top
    Map(:bottom=>"calc(100% + $gap)",
        :left=>"$(target.width/2 - object.width/2)px")
  else
    error("unknown placement: $placement")
  end
end

@mutable Satellite <: AbstractSatellite

dom(ui::AbstractSatellite) = begin
  @dom[:div css"position: relative; display: content"
    ui.firstchild
    [:div{style=position(ui)}
          css"""
          position: absolute
          opacity: 0
          &.show { opacity: 1 }
          transition: opacity 0.6s
          """
          class.show=ui.show && ui.bounds[1].width > 0
      ui.children[end]]]
end
