@use "github.com/jkroso/Prospects.jl" @mutable @struct
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "github.com/jkroso/Units.jl" s ns
@use "../event.jl" ondblclick tick onfocusout onfocusin onkeydown emit Change Submit
@use "../types.jl" UINode Component adopt @ui dom focus

@mutable StringUI(editing=false, cursor=typemax(Int), blink=true) <: Component

dom(ui::StringUI) = begin
  if ui.editing
    str = ui.data
    pos = min(length(str), ui.cursor)
    pre,post = str[1:pos], str[pos+1:end]
    cursor = @dom[:span class.blink = ui.blink
                        css"""
                        display: inline-block
                        background: #5c6df9
                        height: 1.8rem
                        width: 2px
                        opacity: 1
                        position: absolute
                        top: 1px
                        transition: opacity 0.2s ease-in-out
                        &.blink {opacity: 0}
                        """]
    @dom[:span class="syntax--quoted syntax--double syntax--string" css"position: relative"
      '"' pre cursor post '"']
  else
    @dom[:span class="syntax--quoted syntax--double syntax--string" repr(ui.data)]
  end
end

ondblclick(ui::StringUI, event) = focus(ui)

onfocusout(ui::StringUI, event) = begin
  ui.editing = false
end

onfocusin(ui::StringUI, event) = begin
  ui.editing = true
end

const blink_speed = 0.8s

tick(ui::StringUI, event) = begin
  ui.editing || return
  ui.blink = event.time % blink_speed < blink_speed/2
end

onkeydown(ui::StringUI, e) = begin
  value = ui.data
  cursor = min(length(value), ui.cursor)
  if e.key == "Enter"
    emit(ui, Submit(value))
  elseif e.key == "Backspace"
    str = string(value[1:cursor-1], value[cursor+1:end])
    ui.data = str
    ui.cursor = max(ui.cursor - 1, 0)
    emit(ui, Change(str))
  elseif e.key == "Delete"
    str = string(value[1:cursor], value[cursor+2:end])
    ui.data = str
    emit(ui, Change(str))
  elseif e.key == "ArrowLeft"
    ui.cursor = max(cursor - 1, 0)
  elseif e.key == "Home"
    ui.cursor = 0
  elseif e.key == "ArrowRight"
    ui.cursor = min(cursor + 1, length(value))
  elseif e.key == "End"
    ui.cursor = length(value)
  elseif length(e.key) == 1
    str = string(value[1:cursor], e.key, value[cursor+1:end])
    ui.cursor = cursor + 1
    emit(ui, Change(str))
    ui.data = str
  end
end
