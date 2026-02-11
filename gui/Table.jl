@use "github.com/jkroso/DOM.jl" @css_str @dom Container Node
@use "github.com/jkroso/Prospects.jl" @mutable
@use "../types.jl" UINode Component adopt @ui dom children add_child!
@use "./basic.jl" VStack Expandable expansion describe

table(attrs, children) = begin
  @dom[:div{css"""
            border-radius: 0.4rem
            border: 1px solid #e5e7eb
            :where(tbody, thead) > tr > th {font: 1.3rem bolder, verdana}
            width: fit-content
            table
              text-align: left
              width: fit-content
              th {padding: 0.75rem 1.5rem; font: 1.3rem bolder, verdana}
              th,td {padding: 0.75rem 1.5rem}
            """, attrs...}
    [:table children...]]
end

header(attrs, children) = begin
  if get(attrs,:index,true)
    @dom[:thead{attrs...} [:tr [:th] (@dom[:th x] for x in children)...]]
  else
    @dom[:thead{attrs...} [:tr (@dom[:th x] for x in children)...]]
  end
end

body(attrs, children) = @dom[:tbody{attrs...} (get(attrs,:index,true) ? map(add_index, enumerate(children)) : children)...]
add_index((i, tr)::Tuple{Number,Container{:tr}}) = @dom[:tr{tr.attrs...} [:th string(i)] tr.children...]
footer(attrs, children) = begin
  @dom[:tfoot{css"""
              border-top: 1px solid #e5e7eb
              tr > th {text-align: right}
              tr > td {text-align: right}
              tr:not(:last-child) > th {font-weight: lighter; font-family: monospace; color: rgb(130,130,130)}
              tr:last-child > th {font-weight: bolder; font-family: monospace}
              """, attrs...} children...]
end

row(attrs, children) = @dom[:tr{attrs...} map(td, children)...]
td(x::Union{Container{:td}, Container{:th}}) = x
td(x::Union{String, Node}) = @dom[:td x]
td(x::Node) = @dom[:td x]

@mutable Table(index=false) <: Component
dom(ui::Table) = @dom[table{ui.attrs...} (convert(Node, x) for x in ui.children)...]
@mutable Header <: Component
dom(ui::Header) = @dom[header{index=ui.parent.index, ui.attrs...} (convert(Node, x) for x in ui.children)...]
@mutable Body <: Component
dom(ui::Body) = @dom[body{index=ui.parent.index, ui.attrs...} (convert(Node, x) for x in ui.children)...]
@mutable Footer <: Component
dom(ui::Footer) = @dom[footer{ui.attrs...} (convert(Node, x) for x in ui.children)...]
@mutable Row <: Component
dom(ui::Row) = @dom[row{ui.attrs...} (convert(Node, x) for x in ui.children)...]
@mutable Cell <: Component
dom(ui::Cell) = @dom[cell_type(ui) (convert(Node, x) for x in ui.children)...]
cell_type(ui::Cell) = begin
  container = ui.parent.parent
  container isa Header && return Container{:th}
  container isa Footer && return Container{:th}
  return Container{:td}
end

adopt(::Row, x) = @ui[Cell convert(UINode, x)]
adopt(::Row, x::Cell) = x
# Add rows to body rather than to the table itself
add_child!(ui::Table, row::Row, prevsibling::Nothing) = add_child!(ui, @ui[Body row], nothing)
add_child!(ui::Table, row::Row, prevsibling::Header) = add_child!(ui, @ui[Body row], prevsibling)
add_child!(ui::Table, row::Row, prevsibling::Body) = begin
  add_child!(prevsibling, row)
  prevsibling
end

# @dom[table css":is(thead, tbody) tr > :is(th,td):last-child {text-align: right}"
#   [header "Product Name" "Color" "Category" "Price"]
#   [body
#     [row "Apple MacBook Pro 17" "Silver" "Laptop" "\$2999"]
#     [row "Microsoft Surface Pro"	"White"	"Laptop PC"	"\$1999"]
#     [row "Magic Mouse 2"	"Black"	"Accessories"	"\$99"]]
#   [footer css"""
#           tr:first-child > :is(th,td) {padding-top: 2rem}
#           tr > :is(th,td) {padding-top: 0rem}
#           """
#     [row [:th colspan="4" "Subtotal"] raw"$4000"]
#     [row [:th colspan="4" "Tax"] raw"$400"]
#     [row [:th colspan="4" "Total"] raw"$4,400"]]]
#
# describe(ui::Table) = ui
# @ui[Table
#   [Header "Product Name" "Color" "Category" "Price"]
#   [Row "Apple MacBook Pro 17" "Silver" "Laptop" "\$2999"]
#   [Row "Microsoft Surface Pro"	"White"	"Laptop PC"	"\$1999"]
#   [Row "Magic Mouse 2"	"Black"	"Accessories"	"\$99"]]
