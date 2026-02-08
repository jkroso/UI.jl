# Tables
#
# The Table component provides a structured way to display tabular data.
# It consists of Header, Body, Footer, Row, and Cell sub-components.
# Rows added directly to a Table are auto-wrapped in a Body.
# Cells in Rows are auto-wrapped via the adopt() pattern.

@use "../types.jl" @ui dom
@use "../gui/Table.jl" Table Header Body Footer Row Cell
@use "github.com/jkroso/DOM.jl" @dom @css_str

# Basic table with header and rows
table = @ui[Table
  [Header "Product" "Color" "Category" "Price"]
  [Row "MacBook Pro 17\"" "Silver" "Laptop" "\$2999"]
  [Row "Surface Pro" "White" "Laptop PC" "\$1999"]
  [Row "Magic Mouse 2" "Black" "Accessories" "\$99"]]

println("Table structure:")
for section in table.children
  println("  ", typeof(section))
  if hasproperty(section, :firstchild)
    for row in section.children
      print("    ", typeof(row), ": ")
      for cell in row.children
        print("\"", cell.firstchild.value, "\" ")
      end
      println()
    end
  end
end

# Table with footer for totals
full_table = @ui[Table(index=false)
  [Header "Product" "Color" "Category" "Price"]
  [Row "MacBook Pro" "Silver" "Laptop" "\$2999"]
  [Row "Surface Pro" "White" "Laptop" "\$1999"]
  [Row "Magic Mouse" "Black" "Accessories" "\$99"]
  [Footer
    [Row "Subtotal" "" "" "\$5097"]
    [Row "Tax" "" "" "\$510"]
    [Row "Total" "" "" "\$5607"]]]

println("\nFull table with footer created: ", typeof(full_table))
