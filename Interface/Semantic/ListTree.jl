@use "github.com/jkroso/Prospects.jl" @def @abstract
@use "github.com/jkroso/MiniFB.jl/skia" line path move_to line_to
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" UITree SemanticUI describe mixin! add_child! describe! focus
@use "../draw" draw
@use Colors: @colorant_str
@use GeometryBasics: Vec2

@abstract struct TreeItem <: SemanticUI
  selected::Bool = false
end

@def mutable struct Item <: TreeItem end

Item(label::UITree) = begin
  item = Item()
  add_child!(item, label)
  item
end
Item(label::String) = Item(Box(Text(label, size=13pt, color=colorant"rgb(30,30,30)")))

@def mutable struct ItemGroup <: TreeItem
  collapsed::Bool = true
end

ItemGroup(label::UITree, children::TreeItem...) = begin
  group = ItemGroup()
  add_child!(group, label)
  for child in children
    add_child!(group, child)
  end
  group
end
ItemGroup(label::String, children::TreeItem...) =
  ItemGroup(Box(Text(label, size=13pt, color=colorant"rgb(30,30,30)")), children...)

@def mutable struct ListTree <: SemanticUI
  focused::Union{Nothing,TreeItem} = nothing
end

ListTree(children::TreeItem...) = begin
  tree = ListTree()
  for child in children
    add_child!(tree, child)
  end
  isempty(children) || (tree.focused = children[1])
  tree
end

# Navigation helpers

"First sub-item of an ItemGroup (the child after the label)"
first_sub_item(group::ItemGroup) = group.firstchild.nextsibling

"Is this the last sibling among TreeItem children?"
is_last_tree_item(item::TreeItem) = begin
  sib = item.nextsibling
  while sib !== nothing
    sib isa TreeItem && return false
    sib = sib.nextsibling
  end
  true
end

"Next visible item in depth-first order"
next_visible(item::TreeItem) = begin
  if item isa ItemGroup && !item.collapsed
    sub = first_sub_item(item)
    sub !== nothing && return sub
  end
  sib = item.nextsibling
  while sib !== nothing
    sib isa TreeItem && return sib
    sib = sib.nextsibling
  end
  node = item.parent
  while node !== nothing && !(node isa ListTree)
    sib = node.nextsibling
    while sib !== nothing
      sib isa TreeItem && return sib
      sib = sib.nextsibling
    end
    node = node.parent
  end
  nothing
end

"Previous visible item in depth-first order"
prev_visible(item::TreeItem) = begin
  prev = item.prevsibling
  while prev !== nothing && !(prev isa TreeItem)
    prev = prev.prevsibling
  end
  prev !== nothing && return last_visible(prev)
  p = item.parent
  p isa TreeItem ? p : nothing
end

"Last visible descendant of an item"
last_visible(item::Item) = item
last_visible(item::ItemGroup) = begin
  item.collapsed && return item
  last = nothing
  for child in item.children
    child isa TreeItem && (last = child)
  end
  last === nothing ? item : last_visible(last)
end

"Depth of a TreeItem (0 for top-level items in ListTree)"
depth(item::TreeItem) = item.parent isa ListTree ? 0 : 1 + depth(item.parent)

"Walk up n levels from item"
ancestor(item, n) = n == 0 ? item : ancestor(item.parent, n - 1)

# Describe

const INDENT_WIDTH = 20px
const LINE_COLOR = colorant"rgb(190,190,190)"
const FOCUS_BG = colorant"rgb(210,222,240)"
const ROW_HEIGHT = 28px
const CHEVRON_WIDTH = 12px
const CHEVRON_GAP = 4px

describe(tree::ListTree) = begin
  col = Column(width(grow=GrowType.Grow), padding(6px, 4px),
               radius(6px), border(1px, :solid, colorant"rgb(200,200,200)"),
               background(colorant"white"))
  flatten_items!(col, tree, tree.focused)
  col
end

"Recursively flatten visible items into rows in the column"
flatten_items!(col, parent, focused) = begin
  for child in parent.children
    child isa TreeItem || continue
    mixin!(col, describe_item(child, focused))
    if child isa ItemGroup && !child.collapsed
      flatten_items!(col, child, focused)
    end
  end
end

"Recreate a label's geometric tree for use in the describe output"
describe_label(box::Container) = begin
  out = Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow))
  for child in box.children
    if child isa Text
      mixin!(out, Text(child.content, size=child.size, color=child.color,
                       family=child.family, weight=child.weight))
    else
      mixin!(out, describe_label(child))
    end
  end
  out
end
describe_label(t::Text) =
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Text(t.content, size=t.size, color=t.color, family=t.family, weight=t.weight))

"Create a Row for a single item"
describe_item(item::TreeItem, focused) = begin
  d = depth(item)
  row = Row(width(grow=GrowType.Grow), height(ROW_HEIGHT), Alignment.Center)
  row.from = item

  item === focused && mixin!(row, background(FOCUS_BG), radius(4px))

  # Ancestor through-line spacers: render the line as a colored Box
  for i in 1:d-1
    anc = ancestor(item, d - i)
    if !is_last_tree_item(anc)
      mixin!(row, Box(width(INDENT_WIDTH), height(ROW_HEIGHT), Alignment.Center,
                      Box(width(1.5px), height(ROW_HEIGHT), background(LINE_COLOR))))
    else
      mixin!(row, Box(width(INDENT_WIDTH), height(ROW_HEIGHT)))
    end
  end

  # Self-connector spacer (L/T shape drawn by custom draw)
  d > 0 && mixin!(row, Box(width(INDENT_WIDTH), height(ROW_HEIGHT)))

  # Chevron placeholder for ItemGroup (drawn by custom draw)
  if item isa ItemGroup
    mixin!(row, Box(width(CHEVRON_WIDTH), height(ROW_HEIGHT)))
    mixin!(row, Box(width(CHEVRON_GAP)))
  end

  # Label content
  label = item.firstchild
  if label isa SemanticUI
    mixin!(row, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), describe!(label)))
  else
    mixin!(row, describe_label(label))
  end

  row
end

# Draw (self-connector lines + chevron only — ancestor through-lines are GeometricUI)

draw(ctx, size, ui::ConcreteRect, item::TreeItem) = begin
  d = depth(item)
  d == 0 && @goto chevron

  # Self connector (spacer at index d)
  spacer = ui.children[d]
  cx = spacer.left + spacer.width / 2
  right = spacer.left + spacer.width
  mid_y = spacer.top + spacer.height / 2
  r = 4px
  if is_last_tree_item(item)
    path(ctx, color=LINE_COLOR, width=1.5px) do p
      move_to(p, Vec2{px}(cx, spacer.top))
      line_to(p, Vec2{px}(cx, mid_y - r))
      line_to(p, Vec2{px}(cx + r * 0.1, mid_y - r * 0.5))
      line_to(p, Vec2{px}(cx + r * 0.5, mid_y - r * 0.1))
      line_to(p, Vec2{px}(cx + r, mid_y))
      line_to(p, Vec2{px}(right, mid_y))
    end
  else
    line(ctx, Vec2{px}(cx, spacer.top), Vec2{px}(cx, spacer.top + spacer.height), 1.5px, LINE_COLOR)
    path(ctx, color=LINE_COLOR, width=1.5px) do p
      move_to(p, Vec2{px}(cx, mid_y - r))
      line_to(p, Vec2{px}(cx + r * 0.1, mid_y - r * 0.5))
      line_to(p, Vec2{px}(cx + r * 0.5, mid_y - r * 0.1))
      line_to(p, Vec2{px}(cx + r, mid_y))
      line_to(p, Vec2{px}(right, mid_y))
    end
  end

  @label chevron
  if item isa ItemGroup
    chevron_box = ui.children[d + 1]
    cx = chevron_box.left + chevron_box.width / 2
    cy = chevron_box.top + chevron_box.height / 2
    s = 3px
    l = 5px
    color = colorant"rgb(150,150,150)"
    if item.collapsed
      path(ctx, color=color, width=1.5px) do p
        move_to(p, Vec2{px}(cx - s, cy - l))
        line_to(p, Vec2{px}(cx + s, cy))
        line_to(p, Vec2{px}(cx - s, cy + l))
      end
    else
      path(ctx, color=color, width=1.5px) do p
        move_to(p, Vec2{px}(cx - l, cy - s))
        line_to(p, Vec2{px}(cx, cy + s))
        line_to(p, Vec2{px}(cx + l, cy - s))
      end
    end
  end
end

# Keyboard navigation

onkey(tree::ListTree, ::KeyPress{Keys.down}) = begin
  tree.focused === nothing && return
  next = next_visible(tree.focused)
  next !== nothing && (tree.focused = next)
end

onkey(tree::ListTree, ::KeyPress{Keys.up}) = begin
  tree.focused === nothing && return
  prev = prev_visible(tree.focused)
  prev !== nothing && (tree.focused = prev)
end

onkey(tree::ListTree, ::KeyPress{Keys.right}) = begin
  item = tree.focused
  item === nothing && return
  if item isa ItemGroup
    if item.collapsed
      item.collapsed = false
    else
      sub = first_sub_item(item)
      sub !== nothing && (tree.focused = sub)
    end
  end
end

onkey(tree::ListTree, ::KeyPress{Keys.left}) = begin
  item = tree.focused
  item === nothing && return
  if item isa ItemGroup && !item.collapsed
    item.collapsed = true
  elseif item.parent isa TreeItem
    tree.focused = item.parent
  end
end

# Mouse: click to focus

"Find the ListTree ancestor"
find_list_tree(node) = node isa ListTree ? node : find_list_tree(node.parent)

onkey(item::TreeItem, e::KeyPress{Keys.mouse_left}) = begin
  tree = find_list_tree(item)
  tree.focused = item
  focus(tree)
  if item isa ItemGroup
    item.collapsed = !item.collapsed
  end
end

export ListTree, ItemGroup, TreeItem, Item
