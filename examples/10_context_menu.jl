# Context Menu
#
# Demonstrates building a real UI element: a macOS-style context menu
# with border dividers between items, centered in a window.

@use "../Interface/Descriptive"...
@use "../Interface/Specific"...
@use Colors: colorant

# A menu item: full-width box containing centered text
menu_item(label; height=31px) =
  Box(width(grow=GrowType.Grow), Height(preferred=height),
    Text(label, size=16px, family="Helvetica", color=colorant"rgb(80,80,80)"))

# The context menu: a column with border dividers between items
menu = Column(
  width(50mm),
  border(1px, :solid, colorant"rgb(150,150,150)", between=true),
  radius(3px),
  background(colorant"white"),
  menu_item("Copy"),
  menu_item("Paste"),
  menu_item("Cut"),
  menu_item("Select All"))

# Center the menu in a window
window = Box(
  width(grow=GrowType.Grow),
  height(grow=GrowType.Grow),
  Alignment.Center,
  background(colorant"white"),
  menu)

result = resolve(window, (400px, 300px))
println("Context menu layout:")
println("  Window: $(result.width) x $(result.height)")
menu_rect = result.children[1]
println("  Menu: $(menu_rect.width) x $(menu_rect.height)")
println("  Menu position: left=$(menu_rect.left), top=$(menu_rect.top)")
println("  Items:")
for (i, item) in enumerate(menu_rect.children)
  println("    $i. $(item.width) x $(item.height) at top=$(item.top)")
end
