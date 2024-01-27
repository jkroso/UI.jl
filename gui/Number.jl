@use "github.com/jkroso/Units.jl" ms
@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom focus
@use "../event.jl" onmousedown onkeydown ondblclick onfocusout onfocusin tick emit Change Submit
@use "./basic.jl" VStack

@mutable NumberUI(editing=false,
                  cursor=typemax(Int),
                  blink=true,
                  type::Union{DataType,Nothing}=nothing) <: Component

ondblclick(ui::NumberUI, event) = begin
  focus(ui)
end

onfocusout(ui::NumberUI, event) = begin
  ui.editing = false
end

onfocusin(ui::NumberUI, event) = begin
  if isnothing(ui.type)
    ui.type = typeof(ui.data)
  end
  ui.editing = true
end

const blink_speed = 800ms

tick(ui::NumberUI, event) = begin
  ui.editing || return
  ui.blink = event.time % blink_speed < blink_speed/2
end

parse_input(ui::NumberUI, str::AbstractString) = begin
  type = isnothing(ui.type) ? typeof(ui.data) : ui.type
  isempty(str) && return nothing
  parse(type, str)
end

onkeydown(ui::NumberUI, e) = begin
  str = isnothing(ui.data) ? "" : string(ui.data)
  cursor = min(length(str), ui.cursor)
  if e.key == "Enter"
    emit(ui, Submit(ui.data))
  elseif e.key == "Backspace"
    str = string(str[1:cursor-1], str[cursor+1:end])
    data = parse_input(ui, str)
    ui.data = data
    ui.cursor = max(ui.cursor - 1, 0)
    emit(ui, Change(data))
  elseif e.key == "Delete"
    str = string(str[1:cursor], str[cursor+2:end])
    data = parse_input(ui, str)
    ui.data = data
    emit(ui, Change(data))
  elseif e.key == "ArrowLeft"
    ui.cursor = max(cursor - 1, 0)
  elseif e.key == "Home"
    ui.cursor = 0
  elseif e.key == "ArrowRight"
    ui.cursor = min(cursor + 1, length(str))
  elseif e.key == "End"
    ui.cursor = length(str)
  elseif length(e.key) == 1 && occursin(r"[0-9]", e.key)
    str = string(str[1:cursor], e.key, str[cursor+1:end])
    data = parse_input(ui, str)
    ui.cursor = cursor + 1
    ui.data = data
    emit(ui, Change(data))
  end
end

dom(ui::NumberUI) = begin
  str = isnothing(ui.data) ? "" : repr(ui.data)
  if ui.editing
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
    @dom[:span class="syntax--constant syntax--numeric" css"position: relative" pre cursor post]
  else
    @dom[:span class="syntax--constant syntax--numeric" str]
  end
end
