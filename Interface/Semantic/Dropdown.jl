@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! theme scale handled integrate inputs sized
@use "./Icon" Icon
@use "../draw" show_menu! hide_menu! rect cursor family_of
@use Colors: @colorant_str

@def mutable struct Dropdown <: SemanticUI
  selected::Int = 1
  options::Vector{String} = String[]
  onchange::Function = dropdown -> nothing   # called with the dropdown after a click picks another option
  open::Bool = false
  # The font each option is shown in, in the box and in the menu. A font picker gives the fonts
  # themselves, so each name shows in its own font. Empty, or an empty name, uses the theme's font.
  families::Vector{String} = String[]
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
      Text(current_label(d); size=sized(13pt, theme(d)), family_of(d.families, clamp(d.selected, 1, max(1, length(d.options))), theme(d))...)),
    # The arrow is the same thin one a tree has
    Box(width(20px * k), height(grow=GrowType.Grow), Alignment.Center,
      describe!(Icon(d.open ? "chevron-up" : "chevron-down", size=12px * k, color=theme(d).dim))))
end

# A click opens the menu, so the box shows the hand that a button shows
cursor(::Dropdown) = :hand

onkey(d::Dropdown, e::KeyPress{Keys.mouse_left}) = begin
  r = rect(d)
  (isempty(d.options) || r === nothing) && return handled
  if d.open
    d.open = false
    hide_menu!(e.window)
  else
    d.open = true
    # The menu hangs from the box, so it stays with the box when the page scrolls
    show_menu!(e.window, d.options, r.left, r.top + r.height + 2px, r.width, under=d, gap=2px,
               theme=theme(d), item_height=36px * scale(theme(d)), families=d.families,
               onselect=idx -> begin
                 d.open = false
                 (idx > 0 && idx != d.selected) || return
                 d.selected = idx
                 d.onchange(d)
               end)
  end
  handled
end

"The option that's chosen, or `nothing` when there are no options"
integrate(d::Dropdown) = isempty(d.options) ? nothing : current_label(d)

# What `describe` reads, so that it only runs again when one of these changes
inputs(d::Dropdown) = (d.selected, d.options, d.open, d.families)

export Dropdown
