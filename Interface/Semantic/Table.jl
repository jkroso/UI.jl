@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../abstract" SemanticUI UITree describe mixin! add_child! theme scale
@use Colors: @colorant_str

@def mutable struct TableCell <: SemanticUI
  value::String = ""
  header::Bool = false
end
TableCell(value::String) = TableCell(value=value)

@def mutable struct TableRow <: SemanticUI end
TableRow(cells::String...) = begin
  row = TableRow()
  for cell in cells
    add_child!(row, TableCell(cell))
  end
  row
end

@def mutable struct TableHeader <: SemanticUI end
TableHeader(labels::String...) = begin
  hdr = TableHeader()
  for label in labels
    add_child!(hdr, TableCell(value=label, header=true))
  end
  hdr
end

@def mutable struct Table <: SemanticUI end
Table(children::UITree...) = begin
  t = Table()
  for child in children
    add_child!(t, child)
  end
  t
end

describe(cell::TableCell) = begin
  k = scale()
  box = Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(8px * k, 6px * k))
  if cell.header
    mixin!(box, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                    Text(cell.value, size=13pt * k, weight=700)))
  else
    mixin!(box, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                    Text(cell.value, size=13pt * k)))
  end
  box
end

describe(row::TableRow) = begin
  r = Row(width(grow=GrowType.Grow), height(36px * scale()))
  for cell in row.children
    geo = describe(cell)
    geo.from = cell
    mixin!(r, geo)
  end
  r
end

describe(hdr::TableHeader) = begin
  r = Row(width(grow=GrowType.Grow), height(36px * scale()), background(theme().hover))
  for cell in hdr.children
    geo = describe(cell)
    geo.from = cell
    mixin!(r, geo)
  end
  r
end

describe(table::Table) = begin
  col = Column(width(grow=GrowType.Grow),
               radius(6px),
               border(1px, :solid, theme().line, between=true),
               background(theme().surface))
  for child in table.children
    geo = describe(child)
    geo.from = child
    mixin!(col, geo)
  end
  col
end

export Table, TableHeader, TableRow, TableCell
