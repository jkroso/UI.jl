@use "github.com/jkroso/Prospects.jl" @mutable @field_str Field
@use "github.com/jkroso/DOM.jl" @css_str @dom
@use "../types.jl" UINode Component SubComponent @ui dom children onmount
@use "../event.jl" onmousedown onmousemove onmouseup left
@use Colors: hex, HSV, RGB, red, green, blue

@mutable struct ColorPicker <: Component
  color::HSV
end

children(ui::ColorPicker) = UINode[ShadePicker(), HuePicker()]

onmousemove(ui::ColorPicker, event) = begin
  for thumb in map(field"firstchild", ui.children)
    thumb.dragging && ondrag(thumb, event)
  end
end

onmouseup(ui::ColorPicker, event) = begin
  event.button == left || return
  for thumb in map(field"firstchild", ui.children)
    thumb.dragging = false
  end
end

@mutable struct ShadePicker <: SubComponent end
children(ui::ShadePicker) = UINode[ShadePickerThumb()]

@mutable struct ShadePickerThumb <: SubComponent
  position::Vector{Int}=[0,0]
  basis::Vector{Int}=[0,0]
  dragging::Bool=false
end

thumboffset((;s,v)::HSV) = Int[round(Int, 255s), round(Int, 255-(256v))]
thumboffset(ui::ShadePickerThumb) = thumboffset(ui.parent.parent.color)

onmount(ui::ShadePickerThumb) = begin
  setfield!(ui, :position, thumboffset(ui))
end

onmousedown(ui::ShadePicker, event) = begin
  event.button == left || return nothing
  thumb = ui.firstchild
  x,y = ui.dimensions
  thumb.basis = [x, y]
  thumb.position = event.position - thumb.basis
  thumb.dragging = true
end

ondrag(ui::ShadePickerThumb, event) = ui.position = event.position - ui.basis

Base.setproperty!(ui::ShadePickerThumb, ::Field{:position}, (x,y)::Vector) = begin
  picker = ui.parent.parent
  x = min(256, max(0, x))
  y = min(256, max(0, y))
  picker.color = HSV(picker.color.h, x/256, 1-y/256)
  setfield!(ui, :position, [x,y])
end

@mutable struct HuePicker <: SubComponent end
children(ui::HuePicker) = UINode[HuePickerThumb()]
@mutable struct HuePickerThumb <: SubComponent
  position::Integer=0
  dragging::Bool=false
  basis::Integer=0
end

onmount(ui::HuePickerThumb) = begin
  h = ui.parent.parent.color.h
  setfield!(ui, :position, round(Int16, h/360*256))
end

onmousedown(ui::HuePicker, event) = begin
  thumb = ui.firstchild
  thumb.basis = ui.dimensions.x
  thumb.position = event.position[1] - thumb.basis
  thumb.dragging = true
end

ondrag(ui::HuePickerThumb, event) = ui.position = event.position[1] - ui.basis

Base.setproperty!(ui::HuePickerThumb, ::Field{:position}, x::Integer) = begin
  picker = ui.parent.parent
  (;s,v) = picker.color
  x = min(256, max(0, x))
  h = round(Int16, x * 360/256)
  picker.color = HSV(h,s,v)
  setfield!(ui, :position, x)
end

shade_bg(hex) = begin
  """
  linear-gradient(0deg, rgb(0, 0, 0), rgba(0, 0, 0, 0.9) 1%, transparent 99%),\
  linear-gradient(90deg, rgb(255, 255, 255) 1%, transparent),\
  linear-gradient(#$hex, #$hex)\
  """
end

dom(ui::ShadePicker) = begin
  h = ui.parent.color.h
  @dom[:shadepicker css"""
                    width: 256px
                    height: 256px
                    border: 1px solid #181a1f
                    border-radius: 0.4rem
                    position: relative
                    margin-bottom: 20px
                    """
                    style.background=shade_bg(hex(HSV(h, 1, 1)))
    ui.firstchild]
end

dom(ui::ShadePickerThumb) = begin
  (;color) = ui.parent.parent
  x, y = ui.position
  @dom[:thumb css"""
              border-radius: 50%
              width: 26px
              height: 26px
              position: absolute
              border: 1px solid #181a1f
              cursor: pointer
              """
              style.left="$(x - 13)px"
              style.top="$(y - 13)px"
              style.background="#$(hex(color))"]
end

dom(ui::HuePicker) = begin
  @dom[:slider css"""
               height: 2rem
               border-radius: 0.3rem
               background-image: linear-gradient(to right, rgb(255, 0, 0) 0%, rgb(255, 255, 0) 17%, rgb(0, 255, 0) 33%, rgb(0, 255, 255) 50%, rgb(0, 0, 255) 67%, rgb(255, 0, 255) 83%, rgb(255, 0, 0) 100%)
               background-repeat: no-repeat
               background-size: 100% 24px
               position: relative
               """
    ui.firstchild]
end

dom(ui::HuePickerThumb) = begin
  @dom[:thumb css"""
              display: flex
              width: 12px
              height: 3rem
              top: -0.5rem
              border: 3px solid black
              background: transparent
              position: absolute
              cursor: pointer
              border-radius: 3px
              """
              style.left="$(ui.position-6)px"]
end

dom(ui::ColorPicker) = begin
  @dom[:div css"""
            display: flex
            flex-direction: column
            justify-content: center
            padding: 15px
            """
    ui.children...]
end

@ui[ColorPicker(color=HSV(225, 0.8, 0.8))]
