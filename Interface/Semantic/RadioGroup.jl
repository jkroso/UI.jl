@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI describe describe! theme
@use "../draw" draw
@use Colors: @colorant_str

@def mutable struct RadioGroup <: SemanticUI
  selected::Int = 1
  labels::Vector{String} = String[]
end

@def mutable struct RadioItem <: SemanticUI
  group::RadioGroup
  index::Int
end

onkey(item::RadioItem, ::KeyPress{Keys.mouse_left}) = (item.group.selected = item.index)

describe(item::RadioItem) = begin
  selected = item.index == item.group.selected
  t = theme(item)
  circle_color = selected ? t.accent : t.surface
  border_color = selected ? t.accent : t.line
  Row(width(grow=GrowType.Grow), height(28px), padding(2px),
    Box(width(20px), height(20px),
      border(2px, :solid, border_color),
      radius(10px),
      background(circle_color)),
    Box(width(8px), height(20px)),
    Box(height(20px),
      Text(item.group.labels[item.index], size=13pt)))
end

describe(rg::RadioGroup) =
  Column([describe!(RadioItem(group=rg, index=i)) for i in 1:length(rg.labels)]...)

draw(ctx, size, ui::ConcreteRect, item::RadioItem) = begin
  item.index == item.group.selected || return
  box = ui.children[1]
  r = 5px
  cx = box.left + box.width / 2 - r
  cy = box.top + box.height / 2 - r
  rounded_rectangle(ctx, cx, cy, 2r, 2r, r, background=theme(item).on_accent)
end

export RadioGroup
