@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "./Icon" Icon
@use "../abstract" SemanticUI describe add_child! mixin!
@use "../draw" show_menu! hide_menu!
@use Colors: @colorant_str

@def mutable struct Item <: SemanticUI
  icon::Union{Nothing,Icon} = nothing
  label::String = ""
  hover::Bool = false
end

Item(icon::Icon, label::String) = Item(icon=icon, label=label)
Item(label::String) = Item(label=label)

describe(item::Item) = begin
  row = Row(height(32px), width(grow=GrowType.Grow), padding(10px, 0px), radius(4px))
  item.hover && mixin!(row, background(colorant"rgb(220,228,240)"))
  if item.icon !== nothing
    icon_geo = describe(item.icon)
    icon_geo.from = item.icon
    mixin!(row, icon_geo)
    mixin!(row, Box(width(8px)))
  end
  mixin!(row, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                  Text(item.label, size=13pt, color=colorant"rgb(30,30,30)")))
  row
end

@def mutable struct Menu <: SemanticUI
  hover::Int = 0
end

"Called when a menu item is selected. Specialize on your Menu instance's type."
onselect(menu::Menu, idx::Int) = nothing

describe(menu::Menu) = begin
  col_children = Any[width(grow=GrowType.Grow), padding(4px), radius(6px),
                     background("white"), border(1px, :solid, colorant"rgb(200,200,200)")]
  for item in menu.children
    geo = describe(item)
    geo.from = item
    push!(col_children, geo)
  end
  Column(col_children...)
end

show_menu!(window, menu::Menu, x, y, w; item_height=32px) = begin
  show_menu!(window, String[], x, y, w,
             item_height=item_height,
             source=menu,
             onselect=idx -> onselect(menu, idx))
end

export Item, Menu, onselect
