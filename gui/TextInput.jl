@use "github.com/jkroso/Prospects.jl" @mutable @struct
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "github.com/jkroso/Units.jl" s ns
@use "../event.jl" onmousedown tick onfocusout onfocusin onkeydown emit Change Submit
@use "../types.jl" UINode Component adopt @ui dom focus

@mutable TextInput(editing=false,
                   cursor=typemax(Int),
                   blink=true,
                   value="",
                   size=:medium,
                   radius=:medium,
                   placeholder="") <: Component

dom(ui::TextInput) = begin
  str = ui.value
  pos = min(length(str), ui.cursor)
  pre,post = str[1:pos], str[pos+1:end]
  empty = isempty(str)
  if empty && !isempty(ui.placeholder)
    post = ui.placeholder
  end
  cursor = @dom[:span class.blink = ui.blink
                      css"""
                      display: inline-block
                      background: #5c6df9
                      height: 1.8rem
                      width: 2px
                      opacity: 1
                      position: absolute
                      top: 3px
                      transition: opacity 0.2s ease-in-out
                      &.blink {opacity: 0}
                      """]
  @dom[:div{ui.attrs...}
            css"""
            position: relative
            border: 1px solid rgb(180, 180, 180)
            padding: 0.3rem 0.7rem
            min-height: 2.5rem
            min-width: 20rem
            &.empty {color: lightslategray}
            &.editing {border-color: #228be6}
            """
            style.borderRadius = ui.radius == :large ? "2rem" : "3px"
            class.empty = empty
            class.editing = ui.editing
      pre cursor post]
end

onfocusout(ui::TextInput, event) = begin
  ui.editing = false
  ui.blink = true
end

onfocusin(ui::TextInput, event) = begin
  ui.editing = true
end

onmousedown(ui::TextInput, event) = begin
  focus(ui)
end

const blink_speed = 0.8s

tick(ui::TextInput, event) = begin
  if ui.editing
    ui.blink = event.time % blink_speed < blink_speed/2
  end
end

onkeydown(ui::TextInput, e) = begin
  value = ui.value
  cursor = min(length(value), ui.cursor)
  if e.key == "Enter"
    emit(ui, Submit(value))
  elseif e.key == "Backspace"
    str = string(value[1:cursor-1], value[cursor+1:end])
    ui.value = str
    ui.cursor = max(ui.cursor - 1, 0)
    emit(ui, Change(str))
  elseif e.key == "Delete"
    str = string(value[1:cursor], value[cursor+2:end])
    ui.value = str
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
    ui.value = str
  end
end

@ui[TextInput(value="a", placeholder="Type here")]
@ui[TextInput(value="", placeholder="Type here", radius=:large)]
