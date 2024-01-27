@use "github.com/jkroso/Prospects.jl" @mutable @struct
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "github.com/jkroso/Units.jl" s ns
@use "../event.jl" onmousedown tick onfocusout onfocusin onkeydown emit Change
@use "../types.jl" UINode Component adopt @ui dom focus TextNode

@mutable Switch(value=false,
                onLabel::UINode=TextNode("ON"),
                offLabel::UINode=TextNode("OFF")) <: Component

onmousedown(ui::Switch, event) = begin
  ui.value = !ui.value
  emit(ui, Change(ui.value))
end

dom(ui::Switch) = begin
  @dom[:div class.on = ui.value
            css"""
            display: flex
            border-radius: 1rem
            height: 2rem
            width: 4.9rem
            align-items: center
            background: #e9ecef
            color: #949aa2
            position: relative
            &.on {background: #228be6; color: #ffffff}
            > label
              display: grid
              place-content: center
              overflow: hidden
              margin: 0
              height: 2rem
              font-size: 0.8rem
              transition: margin-left 200ms
              transition: color 200ms
              width: 3rem
            > div {transition: left 200ms ease-in-out}
            """
    [:label style.marginLeft = ui.value ? "0" : "2rem"
      ui.value ? ui.onLabel : ui.offLabel]
    [:div css"""
          border-radius: 50%
          height: 1.6rem
          width: 1.6rem
          background: #ffffff
          position: absolute
          top: 0.235rem
          border: .0625rem solid rgb(222,226,230)
          """
          style.left = ui.value ? "3rem" : "0.3rem"]]
end

@ui[Switch]
