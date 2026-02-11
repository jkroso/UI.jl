# Icons
#
# Display all available icons from the Icons folder in a scrollable grid.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe! mixin!
@use "../Interface/Semantic/Icon"...
@use "../Interface/Semantic/SVG"...
@use Colors: @colorant_str

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

const icon_names = sort!([replace(f, ".svg" => "") for f in readdir(normpath(joinpath(@__DIR__(), "../Icons"))) if endswith(f, ".svg")])
const icons_per_row = 12
const icon_size = 20px
const cell_size = 40px

@def mutable struct IconGrid <: SemanticUI
  scroll::Int = 0
end

describe(grid::IconGrid) = begin
  rows_visible = 16
  start = grid.scroll * icons_per_row + 1
  stop = min(start + rows_visible * icons_per_row - 1, length(icon_names))
  col = Column(width(grow=GrowType.Grow), padding(8px))
  row = nothing
  for (i, idx) in enumerate(start:stop)
    if (i - 1) % icons_per_row == 0
      row = Row(padding(4px))
      mixin!(col, row)
    end
    icon = Icon(name=icon_names[idx], color=colorant"rgb(60,60,60)", size=icon_size)
    icon_geo = describe(icon)
    icon_geo.from = icon
    mixin!(row, Box(width(cell_size), height(cell_size), Alignment.Center, icon_geo))
  end
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), background("white"), col)
end

const grid = IconGrid()
const window = Window(grid, title="Icons ($(length(icon_names)))", size=(520px, 700px), animating=true)

onkey(::Window, ::KeyPress{Keys.down}) = begin grid.scroll = min(grid.scroll + 1, length(icon_names) ÷ icons_per_row - 10) end
onkey(::Window, ::KeyPress{Keys.up}) = begin grid.scroll = max(grid.scroll - 1, 0) end
onkey(::Window, ::KeyPress{Keys.pagedown}) = begin grid.scroll = min(grid.scroll + 10, length(icon_names) ÷ icons_per_row - 10) end
onkey(::Window, ::KeyPress{Keys.pageup}) = begin grid.scroll = max(grid.scroll - 10, 0) end

display(window)
