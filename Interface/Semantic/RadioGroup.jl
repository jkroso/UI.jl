@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! theme scale handled integrate inputs sized
@use "../draw" draw cursor
@use Colors: @colorant_str

@def mutable struct RadioGroup <: SemanticUI
  selected::Int = 1
  labels::Vector{String} = String[]
  # Called after a click picks a choice. `group.selected` is the new choice.
  onchange::Function = group -> nothing
end

@def mutable struct RadioItem <: SemanticUI
  group::RadioGroup
  index::Int
end

cursor(::RadioItem) = :hand

onkey(item::RadioItem, ::KeyPress{Keys.mouse_left}) = begin
  item.group.selected = item.index
  item.group.onchange(item.group)
  handled
end

describe(item::RadioItem) = begin
  selected = item.index == item.group.selected
  t = theme(item)
  circle_color = selected ? t.accent : t.surface
  border_color = selected ? t.accent : t.line
  k = scale(t)
  Row(width(grow=GrowType.Grow), height(28px * k), padding(2px * k),
    Box(width(20px * k), height(20px * k),
      border(2px, :solid, border_color),
      radius(10px * k),
      background(circle_color)),
    Box(width(8px * k), height(20px * k)),
    Box(height(20px * k),
      Text(item.group.labels[item.index], size=sized(13pt, t))))
end

describe(rg::RadioGroup) =
  Column([describe!(RadioItem(group=rg, index=i)) for i in 1:length(rg.labels)]...)

draw(ctx, size, ui::ConcreteRect, item::RadioItem) = begin
  item.index == item.group.selected || return
  box = ui.children[1]
  r = 5px * scale(theme(item))
  cx = box.left + box.width / 2 - r
  cy = box.top + box.height / 2 - r
  rounded_rectangle(ctx, cx, cy, 2r, 2r, r, background=theme(item).on_accent)
end

"The label of the choice that's picked, or `nothing` when there are no choices"
integrate(rg::RadioGroup) = isempty(rg.labels) ? nothing : rg.labels[clamp(rg.selected, 1, length(rg.labels))]

# What `describe` reads, so that it only runs again when one of these changes
inputs(rg::RadioGroup) = (length(rg.labels),)
inputs(item::RadioItem) = (item.index, item.group.selected, item.group.labels)

export RadioGroup
