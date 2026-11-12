@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" line path move_to line_to
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe theme
@use "../draw" draw show_menu! hide_menu!
@use Colors: @colorant_str
@use GeometryBasics: Vec2

@def mutable struct Dropdown <: SemanticUI
  selected::Int = 1
  options::Vector{String} = String[]
  onchange::Function = dropdown -> nothing   # called with the dropdown after a click picks another option
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
    border(1px, :solid, theme(d).line),
    radius(4px),
    background(theme(d).surface),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Text(current_label(d), size=13pt)),
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
               theme=theme(d),
               onselect=idx -> begin
                 d.open = false
                 (idx > 0 && idx != d.selected) || return
                 d.selected = idx
                 d.onchange(d)
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
    path(ctx, color=theme(d).dim, width=2px) do p
      move_to(p, Vec2{px}(cx - hw, cy + hh))
      line_to(p, Vec2{px}(cx, cy - hh))
      line_to(p, Vec2{px}(cx + hw, cy + hh))
    end
  else
    path(ctx, color=theme(d).dim, width=2px) do p
      move_to(p, Vec2{px}(cx - hw, cy - hh))
      line_to(p, Vec2{px}(cx, cy + hh))
      line_to(p, Vec2{px}(cx + hw, cy - hh))
    end
  end
end

export Dropdown
