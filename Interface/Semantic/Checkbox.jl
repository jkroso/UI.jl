@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle line
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe add_child! theme scale handled integrate inputs
@use "../draw" draw cursor
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
  t = theme(c)
  box_color = c.checked ? t.accent : t.surface
  border_color = c.checked ? t.accent : t.line
  k = scale(t)
  inner = Row(width(grow=GrowType.Grow), height(24px * k), padding(2px * k),
    Box(width(20px * k), height(20px * k),
      border(2px, :solid, border_color),
      radius(3px * k),
      background(box_color)))
  if !isempty(c.label)
    add_child!(inner, Box(width(8px * k), height(20px * k)))
    add_child!(inner, Box(height(20px * k),
      Text(c.label, size=13pt * k)))
  end
  inner
end

cursor(::Checkbox) = :hand

onkey(c::Checkbox, ::KeyPress{Keys.mouse_left}) = begin
  c.checked = !c.checked
  c.onchange(c)
  handled
end

draw(ctx, size, ui::ConcreteRect, c::Checkbox) = begin
  c.checked || return
  # draw checkmark inside the first child (the box)
  box = ui.children[1]
  k = scale(theme(c))
  x = box.left + 5px * k
  y = box.top + 4px * k
  w = box.width - 10px * k
  h = box.height - 8px * k
  mid_x = x + w * 0.35
  mid_y = y + h
  line(ctx, Vec2{px}(x, y + h*0.5), Vec2{px}(mid_x, mid_y), 2px * k, theme(c).on_accent)
  line(ctx, Vec2{px}(mid_x, mid_y), Vec2{px}(x + w, y), 2px * k, theme(c).on_accent)
end

"Whether the box is ticked"
integrate(c::Checkbox) = c.checked

# What `describe` reads, so that it only runs again when one of these changes
inputs(c::Checkbox) = (c.checked, c.label)

export Checkbox
