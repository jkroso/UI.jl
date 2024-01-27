@use "github.com/jkroso/Prospects.jl" @mutable @struct
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "github.com/jkroso/Units.jl" s ns
@use "../../event.jl" ondblclick tick onfocusout onfocusin onkeydown emit Change Submit
@use "../../types.jl" UINode Component adopt @ui dom focus

@mutable TextField(editing=false,
                   cursor=typemax(Int),
                   blink=true,
                   value="",
                   size="md",
                   radius="md",
                   label="",
                   asterisk=false,
                   description="",
                   error::Union{Bool,String}=false,
                   placeholder="") <: Component

dom(ui::TextField) = begin
  str = ui.value
  pos = min(length(str), ui.cursor)
  pre,post = str[1:pos], str[pos+1:end]
  empty = isempty(str)
  if empty && !isempty(ui.placeholder)
    post = ui.placeholder
  end
  iserrored = ui.error isa Bool ? ui.error : !isempty(ui.error)
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
  @dom[:div css"display: flex; flex-direction: column"
    isempty(ui.label) ?
      nothing :
      @dom[:span css"font-size: 1rem; font-weight: bold; font-family: sans-serif"
        ui.label
        ui.asterisk ? @dom[:span css"color: #f14b4c; padding: 0.3rem" '*'] : nothing]
    isempty(ui.description) ? nothing : @dom[:span css"""
                                                   font-size: 0.7rem
                                                   margin-bottom: 0.5rem
                                                   font-family: sans-serif
                                                   opacity: 0.6
                                                   """ ui.description]
    [:div css"""
          position: relative
          border: 1px solid
          padding: 0.3rem 0.7rem
          height: 2.5rem
          width: 20rem
          &.empty {opacity: 0.5}
          """
          style.borderColor=iserrored ? "#f14b4c" : "rgb(180, 180, 180)"
          style.borderRadius=ui.radius == "large" ? "2rem" : "3px"
          class.empty = empty
      pre cursor post]
    iserrored && !isempty(ui.error) ? @dom[:span css"""
                                                 color: #f14b4c
                                                 font-size: 0.8rem
                                                 font-family: sans-serif
                                                 margin: 0.5rem 0
                                                 """ ui.error] : nothing]
end

onfocusout(ui::TextField, event) = begin
  ui.editing = false
  ui.blink = true
end

onfocusin(ui::TextField, event) = begin
  ui.editing = true
end

const blink_speed = 0.8s

tick(ui::TextField, event) = begin
  if ui.editing
    ui.blink = event.time % blink_speed < blink_speed/2
  end
end

onkeydown(ui::TextField, e) = begin
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

@ui[TextField(value="", label="Address", description="For deliveries", error="Address Not Found", placeholder="Type address here")]
@ui[TextField(value="", label="Address", description="For deliveries", placeholder="Type address here")]
@ui[TextField(value="", label="Address", description="For deliveries", placeholder="Type address here", asterisk=true, radius="large")]
