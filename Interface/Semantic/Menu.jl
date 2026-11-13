@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" onkey KeyPress Keys
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "./Icon" Icon
@use "../abstract" SemanticUI describe add_child! mixin! theme window_of handled
@use "../draw" show_menu! hide_menu! popup! close_popup! ishovered cursor
@use Colors: @colorant_str, RGBA

"One choice in a `Menu`, with an icon beside its label if it's given one"
@def mutable struct Item <: SemanticUI
  icon::Union{Nothing,Icon} = nothing
  label::String = ""
  hover::Bool = false
end

Item(icon::Icon, label::String) = Item(icon=icon, label=label)
Item(label::String) = Item(label=label)

"""
A menu of `Item`s. `show_menu!(window, menu, x, y, width)` floats it over the
app. The mouse or the up and down arrows highlight an item, and a click or
Return picks it.
"""
@def mutable struct Menu <: SemanticUI
  hover::Int = 0   # the item the arrow keys have highlighted, or 0
end

"The place of `item` among its menu's items"
index(item::Item) = findfirst(i -> i === item, collect(item.parent.children))

describe(item::Item) = begin
  menu = item.parent
  row = Row(height(32px), width(grow=GrowType.Grow), padding(10px, 0px), radius(4px))
  lit = item.hover || ishovered(item) || (menu isa Menu && menu.hover == index(item))
  lit && mixin!(row, background(theme(item).select))
  if item.icon !== nothing
    mixin!(row, item.icon)
    mixin!(row, Box(width(8px)))
  end
  mixin!(row, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                  Text(item.label, size=13pt)))
  row
end

"""
Called when an item of a menu is picked, with its place in the menu. It's
called with 0 when the menu closes with nothing picked. Define a method for
your own kind of menu, or for `Menu` if your app has one.
"""
onselect(menu::Menu, idx::Int) = nothing

describe(menu::Menu) =
  Column(width(grow=GrowType.Grow), padding(4px), radius(6px), background(theme(menu).surface),
         border(1px, :solid, theme(menu).line), shadow(0px, 2px, 10px, RGBA(0, 0, 0, 0.1)),
         menu.children...)

"Pick item `idx`: close the menu, then tell `onselect`"
choose!(menu::Menu, idx::Int) = begin
  w = window_of(menu)
  w === nothing || hide_menu!(w)
  menu.hover = 0
  onselect(menu, idx)
  handled
end

cursor(::Item) = :hand
onkey(item::Item, ::KeyPress{Keys.mouse_left}) = choose!(item.parent, index(item))
onkey(menu::Menu, ::KeyPress{Keys.down}) = (menu.hover = mod1(menu.hover + 1, length(menu.children)); handled)
onkey(menu::Menu, ::KeyPress{Keys.up}) = (menu.hover = mod1(menu.hover - 1, length(menu.children)); handled)
onkey(menu::Menu, ::KeyPress{Keys.enter}) = menu.hover > 0 ? choose!(menu, menu.hover) : handled

show_menu!(window, menu::Menu, x, y, w; item_height=32px) = begin
  menu.hover = 0
  popup!(window, menu, anchor=(x, y), width=w, key=:menu, theme=theme(menu), onclose=() -> onselect(menu, 0))
end

export Item, Menu, onselect
