@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" line path move_to line_to
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe
@use "../draw" draw show_menu! hide_menu!
@use Colors: @colorant_str
@use GeometryBasics: Vec2

@def mutable struct Dropdown <: SemanticUI
  selected::Int = 1
  options::Vector{String} = String[]
  open::Bool = false
  cached_left::px = 0px
  cached_top::px = 0px
  cached_width::px = 0px
  cached_height::px = 0px
end

current_label(d::Dropdown) = isempty(d.options) ? "" : d.options[clamp(d.selected, 1, length(d.options))]

describe(d::Dropdown) =
  Row(width(grow=GrowType.Grow), height(36px),
    padding(8px),
    border(1px, :solid, colorant"rgb(200,200,200)"),
    radius(4px),
    background(colorant"white"),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Text(current_label(d), size=13pt, color=colorant"rgb(30,30,30)")),
    Box(width(20px), height(grow=GrowType.Grow)))

onkey(d::Dropdown, e::KeyPress{Keys.mouse_left}) = begin
  isempty(d.options) && return
  if d.open
    d.open = false
    hide_menu!(e.window)
  else
    d.open = true
    show_menu!(e.window, d.options,
               d.cached_left, d.cached_top + d.cached_height + 2px, d.cached_width,
               onselect=idx -> begin
                 idx > 0 && (d.selected = idx)
                 d.open = false
               end)
  end
end

draw(ctx, size, ui::ConcreteRect, d::Dropdown) = begin
  # cache position for show_menu! placement
  d.cached_left = ui.left
  d.cached_top = ui.top
  d.cached_width = ui.width
  d.cached_height = ui.height
  # draw chevron
  chevron_box = ui.children[end]
  cx = chevron_box.left + chevron_box.width / 2
  cy = chevron_box.top + chevron_box.height / 2
  hw = 4px
  hh = 3px
  if d.open
    path(ctx, color=colorant"rgb(120,120,120)", width=2px) do p
      move_to(p, Vec2{px}(cx - hw, cy + hh))
      line_to(p, Vec2{px}(cx, cy - hh))
      line_to(p, Vec2{px}(cx + hw, cy + hh))
    end
  else
    path(ctx, color=colorant"rgb(120,120,120)", width=2px) do p
      move_to(p, Vec2{px}(cx - hw, cy - hh))
      line_to(p, Vec2{px}(cx, cy + hh))
      line_to(p, Vec2{px}(cx + hw, cy - hh))
    end
  end
end

export Dropdown
