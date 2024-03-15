@use "github.com/jkroso/Prospects.jl" @mutable @field_str Field @abstract
@use "github.com/jkroso/Units.jl" mm
@use "github.com/jkroso/DOM.jl" @css_str @dom Map
@use "../types.jl" UINode Component SubComponent @ui dom children onmount
@use "../event.jl" onmousedown onmousemove onmouseup left onmouseover onmouseout

@abstract struct AbstractSatellite <: Component
  bounds::Vector=fill((x=0, y=0, width=0.0, height=0.0), 2)
  show::Bool=false
  placement::Symbol=:bottom
end

onmount(ui::AbstractSatellite) = begin
  ui.bounds = map(field"dimensions", ui.children)
end

position((;bounds,placement)::AbstractSatellite) = begin
  target,object = bounds
  if placement == :bottom
    Map(:top=>"calc(100% + 2px)",
        :left=>"$(target.width/2 - object.width/2)px")
  elseif placement == :right
    Map(:top=>"$(target.height/2 - object.height/2)px",
        :left=>"calc(100% + 2px)")
  elseif placement == :left
    Map(:top=>"$(target.height/2 - object.height/2)px",
        :right=>"calc(100% + 2px)")
  elseif placement == :top
    Map(:bottom=>"calc(100% + 2px)",
        :left=>"$(target.width/2 - object.width/2)px",
        :top=>"auto")
  else
    error("unknown placement: $placement")
  end
end

@mutable Satellite <: AbstractSatellite

dom(ui::Satellite) = begin
  @dom[:div css"""
            position: relative
            display: content
            margin: 5rem
            """
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

@use "./basic.jl" Padding

@ui[Satellite(show=true, placement=:top)
  [Padding(top=2mm,
           bottom=2mm,
           right=3mm,
           left=3mm) class=css"""
                           padding: 1rem
                           border: 1px solid #000000
                           """
    "target"]
  [Padding(top=2mm,
           bottom=2mm,
           right=3mm,
           left=3mm) class=css"""
                           border: 1px solid #000000
                           border-radius: 0.2rem
                           padding: 1rem
                           """
    "Satellite"]]

@ui[Satellite(show=true, placement=:top) [Padding "a"] [Padding "b"]]
