@use "github.com/jkroso/Prospects.jl" @mutable @struct Field @property
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "github.com/jkroso/Units.jl" s ns mm
@use "../event.jl" onmousedown tick onfocusout onfocusin onkeydown emit Change Submit Keys
@use "../types.jl" UINode Component adopt @ui dom focus children tree
@use "../style" @style_str tocss
@use "./basic" dom_attrs HStack

const alphanumeric = Keys.a:getproperty(Keys, Symbol(9))

@struct Cursor(start::UInt16, stop::UInt16)
Cursor(position) = Cursor(position, position)
@property Cursor.position = self.stop

@mutable struct TextInput <: Component
  cursor = Cursor(typemax(UInt16))
  value = ""
  placeholder = ""
  editing = false
  blink = true
end

visualize(ui::TextInput) = begin
  @ui[HBox style"""
           padding: 3mm
           margin: 1mm
           radius: 3mm
           border: 1px solid $(t.editing ? "#228be6" : "#b4b4b4")
           text.color: $(isempty(t.value) ? "#789" : "black")
           """
    isempty(ui.value) ? ui.placeholder : ui.value
    visualize_cursor(ui.value, ui.cursor)]
end

visualize_cursor(str, cursor) = begin
  @ui[HStack style"""
             background: blue
             height: 8mm
             width: 1mm
             offset: 0mm $(cursor.position * 3mm)
             relative: cl cl
             """]
end

visualize_cursor("abc", Cursor(2))

dom(ui::TextInput) = begin
  str = ui.value
  pos = min(length(str), ui.cursor)
  pre, post = str[1:pos], str[pos+1:end]
  empty = isempty(str)
  if empty && !isempty(ui.placeholder)
    post = ui.placeholder
  end
  top = !isnothing(ui.style) && haskey(ui.style, :padding) ? tocss(ui.style[:padding].top) : "3px"
  cursor = @dom[:span class.blink=ui.blink
                      css"""
                      display: inline-block
                      background: #5c6df9
                      height: 1.8rem
                      width: 2px
                      opacity: 1
                      position: absolute
                      transition: opacity 0.2s ease-in-out
                      &.blink {opacity: 0}
                      """
                      style.top = top]
    @dom[:div{dom_attrs(ui)...}
              css"""
              position: relative
              border: 1px solid rgb(180, 180, 180)
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
  ui.editing || return
  ui.blink = event.time % blink_speed < blink_speed / 2
end

onkeydown(ui::TextInput, key::Keys) = begin
  value = ui.value
  cursor = min(length(value), ui.cursor)
  if Keys.return == key
    emit(ui, Submit(value))
  elseif Keys.backspace == key
    str = string(value[1:cursor-1], value[cursor+1:end])
    ui.value = str
    ui.cursor = max(ui.cursor - 1, 0)
    emit(ui, Change(str))
  elseif Keys.delete == key
    str = string(value[1:cursor], value[cursor+2:end])
    ui.value = str
    emit(ui, Change(str))
  elseif Keys.left == key
    ui.cursor = max(cursor - 1, 0)
  elseif Keys.home == key
    ui.cursor = 0
  elseif Keys.right == key
    ui.cursor = min(cursor + 1, length(value))
  elseif Keys.end == key
    ui.cursor = length(value)
  elseif key in alphanumeric | Keys.space | Keys.shft && key != Keys.shft
    char = tochar(key)
    str = string(value[1:cursor], char, value[cursor+1:end])
    ui.cursor = cursor + 1
    emit(ui, Change(str))
    ui.value = str
  end
end

const alphabet = Keys.a:Keys.z
const numbers = getproperty(Keys, Symbol(0)):getproperty(Keys, Symbol(9))
const mods = Keys.shft | Keys.ctrl | Keys.opt | Keys.cmd

tochar(n::Keys) = begin
  n == Keys.space && return ' '
  k = setdiff(n, mods)
  offset = k in numbers ? 10 : Keys.shft in n ? 53 : 85
  Char(log2(k.value) + offset)
end

t = @ui[TextInput(value="a", placeholder="Type here") style"padding: 3mm; margin[top,bottom]: 3mm"]
style(t)
# @ui[TextInput(value="", placeholder="Type here", radius=:large) style"padding: 2mm 5mm; margin[top,bottom]: 3mm"]
