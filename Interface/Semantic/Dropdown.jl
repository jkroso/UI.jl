@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! theme scale
@use "./Icon" Icon
@use "../draw" draw show_menu! hide_menu!
@use Colors: @colorant_str

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

describe(d::Dropdown) = begin
  k = scale(theme(d))
  Row(width(grow=GrowType.Grow), height(36px * k),
    padding(8px * k),
    border(1px, :solid, theme(d).line),
    radius(4px),
    background(theme(d).surface),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Text(current_label(d), size=13pt * k)),
    # The arrow is the same thin one a tree has
    Box(width(20px * k), height(grow=GrowType.Grow), Alignment.Center,
      describe!(Icon(d.open ? "chevron-up" : "chevron-down", size=12px * k, color=theme(d).dim))))
end

onkey(d::Dropdown, e::KeyPress{Keys.mouse_left}) = begin
  isempty(d.options) && return
  if d.open
    d.open = false
    hide_menu!(e.window)
  else
    d.open = true
    show_menu!(e.window, d.options,
               d.cached_left, d.cached_top + d.cached_height + 2px, d.cached_width,
               theme=theme(d), item_height=32px * scale(theme(d)),
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
end

export Dropdown
