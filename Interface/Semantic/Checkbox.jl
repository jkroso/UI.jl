@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" sk_color
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe add_child! theme scale handled integrate inputs sized
@use "../draw" draw cursor
@use Colors: @colorant_str, RGBA

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
  # The box and label sit where a RadioGroup's circle and label do, so the two line up
  inner = Row(width(grow=GrowType.Grow), height(24px * k), padding(2px * k, 2px * k, 2px * k, 4px * k), child_gap=10px * k,
    Box(width(16px * k), height(16px * k),
      border(2px, :solid, border_color),
      radius(3px * k),
      background(box_color)))
  isempty(c.label) || add_child!(inner, Box(height(20px * k), Text(c.label, size=sized(13pt, t))))
  inner
end

cursor(::Checkbox) = :hand

onkey(c::Checkbox, ::KeyPress{Keys.mouse_left}) = begin
  c.checked = !c.checked
  c.onchange(c)
  handled
end

# The tick is one smooth stroke, with round ends and a round corner. Its three points are
# fractions of the box, so it keeps its shape at any size.
const tick = ((0.27, 0.53), (0.43, 0.69), (0.74, 0.33))

draw(ctx, size, ui::ConcreteRect, c::Checkbox) = begin
  c.checked || return
  box = ui.children[1]
  point(f) = (flt(box.left + box.width * f[1]), flt(box.top + box.height * f[2]))
  path = Skia.sk_path_new()
  Skia.sk_path_move_to(path, point(tick[1])...)
  Skia.sk_path_line_to(path, point(tick[2])...)
  Skia.sk_path_line_to(path, point(tick[3])...)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(theme(c).on_accent))
  Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1))
  Skia.sk_paint_set_stroke_width(paint, flt(box.width * 0.13))
  Skia.sk_paint_set_stroke_cap(paint, Skia.SK_STROKE_CAP_ROUND)
  Skia.sk_paint_set_stroke_join(paint, Skia.SK_STROKE_JOIN_ROUND)
  Skia.sk_canvas_draw_path(ctx, path, paint)
  Skia.sk_paint_delete(paint)
  Skia.sk_path_delete(path)
end

"Whether the box is ticked"
integrate(c::Checkbox) = c.checked

# What `describe` reads, so that it only runs again when one of these changes
inputs(c::Checkbox) = (c.checked, c.label)

export Checkbox
