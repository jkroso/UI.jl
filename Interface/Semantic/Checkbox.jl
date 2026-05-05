@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle line
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe add_child!
@use "../draw" draw
@use Colors: @colorant_str, RGBA
@use GeometryBasics: Vec2

@def mutable struct Checkbox <: SemanticUI
  checked::Bool = false
  label::String = ""
  # Called after a click toggles `checked`. Use this to mirror the value
  # into an external source of truth so the Checkbox can be driven as a
  # controlled component (e.g. `Checkbox(checked=item.done,
  # onchange=c -> item.done = c.checked)`).
  onchange::Function = c -> nothing
end

describe(c::Checkbox) = begin
  box_color = c.checked ? colorant"rgb(59,130,246)" : colorant"rgb(255,255,255)"
  border_color = c.checked ? colorant"rgb(59,130,246)" : colorant"rgb(180,180,180)"
  inner = Row(width(grow=GrowType.Grow), height(24px), padding(2px),
    Box(width(20px), height(20px),
      border(2px, :solid, border_color),
      radius(3px),
      background(box_color)))
  if !isempty(c.label)
    add_child!(inner, Box(width(8px), height(20px)))
    add_child!(inner, Box(height(20px),
      Text(c.label, size=13pt, color=colorant"rgb(30,30,30)")))
  end
  inner
end

onkey(c::Checkbox, ::KeyPress{Keys.mouse_left}) = begin
  c.checked = !c.checked
  c.onchange(c)
end

draw(ctx, size, ui::ConcreteRect, c::Checkbox) = begin
  c.checked || return
  # draw checkmark inside the first child (the box)
  box = ui.children[1]
  x = box.left + 5px
  y = box.top + 4px
  w = box.width - 10px
  h = box.height - 8px
  mid_x = x + w * 0.35
  mid_y = y + h
  line(ctx, Vec2{px}(x, y + h*0.5), Vec2{px}(mid_x, mid_y), 2px, colorant"white")
  line(ctx, Vec2{px}(mid_x, mid_y), Vec2{px}(x + w, y), 2px, colorant"white")
end

export Checkbox
