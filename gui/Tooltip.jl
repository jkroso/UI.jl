@use "github.com/jkroso/Prospects.jl" @mutable @field_str Field
@use "github.com/jkroso/Units.jl" mm
@use "github.com/jkroso/DOM.jl" @css_str @dom Map
@use "../types.jl" Component @ui dom children onmount @style_str
@use "../event.jl" onmouseover onmouseout
@use "./Satellite.jl" AbstractSatellite position

@mutable Tooltip <: AbstractSatellite

onmouseover(ui::Tooltip, event) = begin
  ui.show = true
end

onmouseout(ui::Tooltip, event) = begin
  ui.show = false
end

dom(ui::Tooltip) = begin
  @dom[:div css"position: relative; display: content"
    ui.firstchild
    [:div css"""
          position: absolute
          opacity: 0
          &.show { opacity: 1 }
          transition: opacity 0.6s
          > svg
            position: absolute
            background: #31363f
          &.bottom
            padding-top: 10px
            > svg { left: calc(50% - 10px); top: -1px }
            > .content { box-shadow: -2px 2px 5px rgba(0,0,0,0.5) }
          &.top
            padding-bottom: 10px
            > svg { left: calc(50% - 10px); top: calc(100% - 11px); transform: rotate(180deg) }
            > .content { box-shadow: -2px -2px 5px rgba(0,0,0,0.5) }
          &.right
            padding-left: 10px
            > svg { left: -5px; top: calc(50% - 6px); transform: rotate(-90deg) }
            > .content { box-shadow: 2px 2px 5px rgba(0,0,0,0.5) }
          &.left
            padding-right: 10px
            > svg { left: calc(100% - 15px); top: calc(50% - 6px); transform: rotate(90deg) }
            > .content { box-shadow: -2px 2px 5px rgba(0,0,0,0.5) }
          > .content
            border: 1px solid #000000
            border-radius: 0.3rem
          """
          class.show=ui.show && ui.bounds[1].width > 0
          style=position(ui)
          class=ui.placement
      arrow
      [:div class=:content ui.children[end]]]]
end

const arrow = @dom[:svg viewBox="0 0 20 12" width="20" height="12"
  [:path fill="none" stroke="rgb(0, 0, 0)" d="m 0,12 a -8,-8 45 0 0 4,-4 l 4,-6 a 2,-2 45 0 1 4,0 l 4,6 a -8,-8 45 0 0 4,4"]]

#
# @use "./basic.jl" HStack
# @ui[HStack style"padding: 20mm; padding[left,right]: 35mm"
#   [Tooltip(show=true, placement=:bottom)
#     [HStack style"padding: 1mm; padding[left,right]: 3mm; border: 0.3mm; radius: 1mm" "target"]
#     [HStack style"padding[left,right]: 2mm; padding[top,bottom]: 1mm" "satellite"]]]
