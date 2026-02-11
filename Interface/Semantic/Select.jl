@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" line path move_to line_to
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe
@use "../draw" draw
@use Colors: @colorant_str
@use GeometryBasics: Vec2

@def mutable struct Select <: SemanticUI
  selected::Int = 1
  options::Vector{String} = String[]
end

current_label(s::Select) = isempty(s.options) ? "" : s.options[clamp(s.selected, 1, length(s.options))]

describe(s::Select) =
  Row(width(grow=GrowType.Grow), height(36px),
    padding(8px),
    border(1px, :solid, colorant"rgb(200,200,200)"),
    radius(4px),
    background(colorant"white"),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Text(current_label(s), size=13pt, color=colorant"rgb(30,30,30)")),
    Box(width(20px), height(grow=GrowType.Grow)))

onkey(s::Select, ::KeyPress{Keys.mouse_left}) = begin
  isempty(s.options) && return
  s.selected = mod1(s.selected + 1, length(s.options))
end

draw(ctx, size, ui::ConcreteRect, s::Select) = begin
  # draw chevron in the last child box
  chevron_box = ui.children[end]
  cx = chevron_box.left + chevron_box.width / 2
  cy = chevron_box.top + chevron_box.height / 2
  hw = 4px  # half-width of chevron
  hh = 3px  # half-height of chevron
  path(ctx, color=colorant"rgb(120,120,120)", width=2px) do p
    move_to(p, Vec2{px}(cx - hw, cy - hh))
    line_to(p, Vec2{px}(cx, cy + hh))
    line_to(p, Vec2{px}(cx + hw, cy - hh))
  end
end

export Select
