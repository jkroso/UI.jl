@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"... int
@use "github.com/jkroso/Font.jl/units" em
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle line
@use GeometryBasics: Vec2
@use Colors: Colorant, RGB, RGBA, @colorant_str, alpha, hex, red, green, blue
@use "./Geometric"... Dimension
@use "./Specific"...
@use "./abstract" SemanticUI ConcreteUI WrapMode reuse!
@use "./draw" draw set_tool! clear_tool! window_tool app_size draw_tool tool_input inside offset! semantic_source _scenes

const C_PANEL = colorant"rgb(58,56,53)"
const C_STRIPE = colorant"rgb(63,61,58)"
const C_HEADER = colorant"rgb(46,44,42)"
const C_LINE = colorant"rgb(84,80,76)"
const C_GUIDE = colorant"rgb(98,94,90)"
const C_TEXT = colorant"rgb(238,232,226)"
const C_DIM = colorant"rgb(165,157,150)"
const C_FADED = colorant"rgb(118,112,106)"
const C_CLOSE = colorant"rgb(168,66,28)"
const C_HOVER_APP = RGBA(105/255, 210/255, 231/255, 0.45)
const C_HOVER_ROW = colorant"rgb(122,72,62)"
const C_PINNED_ROW = colorant"rgb(112,86,52)"
const C_SELECTED = RGBA(225/255, 138/255, 50/255, 0.35)
const ROW_HEIGHT = 24px
const INDENT = 16px
const FONT = "Helvetica"

"A colour for each badge, so the tree is easy to scan"
const BADGES = Dict(
  "Row" => colorant"rgb(77,124,163)",
  "Column" => colorant"rgb(98,140,92)",
  "Box" => colorant"rgb(128,121,115)",
  "Stack" => colorant"rgb(150,110,90)",
  "Scroll" => colorant"rgb(176,170,62)",
  "Image" => colorant"rgb(66,150,110)",
  "Wedge" => colorant"rgb(168,92,128)",
  "Text" => colorant"rgb(64,140,152)",
  "Background" => colorant"rgb(190,110,60)",
  "Border" => colorant"rgb(116,104,176)",
  "Clip" => colorant"rgb(156,92,146)")

"""
A panel down the right of the window that shows the app's tree while it runs.
The Layout tab shows every element the layout made. The Semantic tab shows only
the app's own nodes, the ones that are a SemanticUI. Click a row to select its element and see how it was sized. To select an
element by pointing at it, click the pick button at the top left of the panel,
then click the element in the app. Escape puts the pick button back. Hover a row
to highlight its element's box, and click a row's −/+ box to collapse or expand it.
"""
@def mutable struct LayoutInspector
  panel_width::px = 400px
  scroll::Scroll = Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                          scrollbar=ScrollbarMode.always, scrollbar_color=RGBA(1, 1, 1, 0.3),
                          scrollbar_track=RGBA(0, 0, 0, 0))
  viewport::px = 0px
  collapsed::Set{Vector{Int}} = Set{Vector{Int}}()
  # Where things landed in the last frame, so clicks and hovers can find them.
  # Rows hold paths rather than elements because the app's layout is usually
  # rebuilt every frame, so last frame's elements aren't in this frame's tree.
  rows::Vector{Tuple{ConcreteRect,Vector{Int}}} = Tuple{ConcreteRect,Vector{Int}}[]
  toggles::Vector{Tuple{ConcreteRect,Vector{Int}}} = Tuple{ConcreteRect,Vector{Int}}[]
  close::Any = nothing
  pick::Any = nothing
  view::Symbol = :layout   # :layout shows every element, :semantic only the app's own nodes
  tabs::Vector{Tuple{ConcreteRect,Symbol}} = Tuple{ConcreteRect,Symbol}[]
  hovered::Any = nothing
  selected::Vector{Int} = Int[]
  picking::Bool = false    # true while the next click in the app selects an element
  swallow::Bool = false    # true until the mouse button of that click comes back up
  reveal::Bool = false     # scroll the tree to the selected element's row
end

"Open the layout inspector in `w`, or close it if it's already open"
toggle_inspector!(w) = window_tool(w) isa LayoutInspector ? clear_tool!(w) : set_tool!(w, LayoutInspector())

app_size(ins::LayoutInspector, size) = Vec2{px}(max(120px, size[1] - ins.panel_width), size[2])

"Every node in the tree, depth first, with its depth"
flatten(node::ConcreteUI, depth=0, out=Tuple{ConcreteUI,Int}[]) = begin
  push!(out, (node, depth))
  node isa ConcreteRect && foreach(c -> flatten(c, depth + 1, out), node.children)
  out
end

"""
The rows the tree shows: one per element, plus one for each Text's content,
skipping the insides of collapsed elements.
"""
function tree_entries(ins::LayoutInspector, node::ConcreteUI, depth=0, path=Int[], out=NamedTuple[])
  haschildren = node isa ConcreteRect && !isempty(node.children)
  push!(out, (kind=:element, node=node, depth=depth, path=path, haschildren=haschildren))
  node isa ConcreteText && push!(out, (kind=:content, node=node, depth=depth + 1, path=path, haschildren=false))
  if haschildren && !(path in ins.collapsed)
    for (i, child) in enumerate(node.children)
      tree_entries(ins, child, depth + 1, [path; i], out)
    end
  end
  out
end

"""
The rows the Semantic tab shows: one for each element that a semantic node made,
set under the semantic node around it.
"""
function semantic_entries(ins::LayoutInspector, node::ConcreteUI, depth=0, path=Int[], out=NamedTuple[])
  node isa ConcreteRect || return out
  owned = semantic_owner(node) !== nothing
  inner = owned ? NamedTuple[] : out
  for (i, child) in enumerate(node.children)
    semantic_entries(ins, child, depth + owned, [path; i], inner)
  end
  owned || return out
  push!(out, (kind=:element, node=node, depth=depth, path=path, haschildren=!isempty(inner)))
  path in ins.collapsed || append!(out, inner)
  out
end

inspector_entries(ins::LayoutInspector, scene) = ins.view == :semantic ? semantic_entries(ins, scene) : tree_entries(ins, scene)

"The element a semantic node made that's nearest around `node`, or `node` itself"
owned(node) = begin
  while node isa ConcreteUI
    semantic_owner(node) === nothing || return node
    node = node.parent isa ConcreteRect && node.parent.from !== nothing ? node.parent : nothing
  end
  nothing
end

"""
The part of each element you can see: what's left of it inside the app's area
after every Scroll or clipping container around it has cut it down. An element
maps to `nothing` when none of it is in view.
"""
function visible_areas(scene::ConcreteRect, app_w, h)
  areas = IdDict{ConcreteUI,Any}()
  walk(node, clip) = begin
    area = clip === nothing ? nothing : overlap(node, clip)
    areas[node] = area
    node isa ConcreteRect || return
    # Children of a clipping container can only show inside it. Other
    # containers let their children overflow, so the clip passes straight on.
    inner = node.from isa Scroll || node.from.clip ? area : clip
    foreach(child -> walk(child, inner), node.children)
  end
  walk(scene, (0px, 0px, app_w, h))
  areas
end

overlap(node::ConcreteUI, (l, t, r, b)) = begin
  l2, t2 = max(l, node.left), max(t, node.top)
  r2, b2 = min(r, node.left + node.width), min(b, node.top + node.height)
  l2 <= r2 && t2 <= b2 ? (l2, t2, r2, b2) : nothing
end

"The tree row for `node`, or for its nearest ancestor when it's inside a collapsed element"
row_index(entries, node) = begin
  while node isa ConcreteUI
    i = findfirst(e -> e.kind == :element && e.node === node, entries)
    i === nothing || return i
    node = node.parent isa ConcreteRect && node.parent.from !== nothing ? node.parent : nothing
  end
  nothing
end

"Scroll the tree so row `i` is in view, if it isn't already"
reveal!(ins, i, rows) = begin
  ins.viewport > 0px || return
  top = (i - 1) * ROW_HEIGHT
  ins.scroll.offset <= top && top + ROW_HEIGHT <= ins.scroll.offset + ins.viewport && return
  max_offset = max(0px, rows * ROW_HEIGHT - ins.viewport)
  ins.scroll.offset = clamp(top - (ins.viewport - ROW_HEIGHT) / 2, 0px, max_offset)
end

"The deepest element containing `pos`"
deepest_at(node::ConcreteRect, pos) = begin
  inside(node, pos) || return nothing
  for child in Iterators.reverse(node.children)
    found = deepest_at(child, pos)
    found === nothing || return found
  end
  node
end
deepest_at(node::ConcreteText, pos) = inside(node, pos) ? node : nothing

"The path from `scene` down to `node`: which child to take at each level"
path_to(scene::ConcreteUI, node::ConcreteUI) = begin
  path = Int[]
  while node !== scene
    pushfirst!(path, findfirst(c -> c === node, node.parent.children))
    node = node.parent
  end
  path
end

"Select the element at `path`, and open every element around it so its row shows"
select!(ins, path) = begin
  ins.selected = path
  filter!(c -> !(length(c) < length(path) && c == path[1:length(c)]), ins.collapsed)
  ins.reveal = true
end

follow(scene::ConcreteUI, path) = begin
  node = scene
  for i in path
    node isa ConcreteRect && i <= length(node.children) || return nothing
    node = node.children[i]
  end
  node
end

"The semantic node this element is the outermost geometry of, if any"
semantic_owner(node::ConcreteRect) = begin
  s = node.from.from
  s isa SemanticUI ? s : nothing
end
semantic_owner(::ConcreteText) = nothing

"What the tree calls an element: its name, or the semantic node that made it"
element_name(node::ConcreteRect) = begin
  isempty(node.from.name) || return node.from.name
  owner = semantic_owner(node)
  owner === nothing ? "" : string(nameof(typeof(owner)))
end
element_name(::ConcreteText) = ""

kind(node::ConcreteRect) = string(nameof(typeof(node.from)))
kind(::ConcreteText) = "Text"

"Badges for what an element is and what it draws"
badges(node::ConcreteText) = ["Text"]
badges(node::ConcreteRect) = begin
  ui = node.from
  out = [kind(node)]
  alpha(ui.background.color) > 0 && push!(out, "Background")
  isempty(ui.border) && isempty(ui.border.between) || push!(out, "Border")
  ui.clip && push!(out, "Clip")
  out
end

preview(s::AbstractString, n=36) = length(s) <= n ? s : first(s, n-1) * "…"

small(s, colour=C_TEXT; size=12px) = Text(String(s), size=size, family=FONT, color=colour, wrap=WrapMode.none)

fade(c::Colorant, a) = RGBA(red(c), green(c), blue(c), a)

badge(label, seen=true) = begin
  c = get(BADGES, label, C_DIM)
  Box(padding(5px, 2px), radius(3px), background(fade(c, seen ? 0.32 : 0.1)), border(1px, :solid, fade(c, seen ? 1 : 0.4)),
    small(label, seen ? C_TEXT : C_FADED, size=11px))
end

"The vertical line that joins a parent to its children"
guide() = Box(width(preferred=INDENT, min=INDENT), height(grow=GrowType.Grow), Alignment.Start, padding(0px, 0px, 0px, 5px),
  Box(width(1px), height(grow=GrowType.Grow), background(C_GUIDE)))

# The −, + and × are drawn as lines once the panel is laid out. As text they sit off centre.
toggle() = Box(width(11px), height(11px), radius(2px), border(1px, :solid, C_DIM))

"Draw a −, + or × in the middle of `box`, with arms `r` long"
symbol(ctx, box::ConcreteRect, what::Symbol, r=2.5px) = begin
  x, y = box.left + box.width/2, box.top + box.height/2
  arms = what == :cross ? (((-r, -r), (r, r)), ((-r, r), (r, -r))) :
         what == :plus ? (((-r, 0px), (r, 0px)), ((0px, -r), (0px, r))) : (((-r, 0px), (r, 0px)),)
  for ((x1, y1), (x2, y2)) in arms
    line(ctx, (x + x1, y + y1), (x + x2, y + y2), 1px, C_TEXT)
  end
end

bullet() = Box(width(11px), height(11px), Alignment.Center, Box(width(5px), height(5px), background(C_DIM)))

"A row of the tree. Elements that are out of view are drawn faded, like Clay does."
function tree_row(ins, entry, fill, seen)
  marker = entry.kind == :content ? Box(width(11px)) :
           entry.haschildren ? toggle() : bullet()
  label = if entry.kind == :content
    Any[small(repr(preview(entry.node.from.content)), seen ? C_DIM : C_FADED)]
  else
    name = ins.view == :semantic ? string(nameof(typeof(semantic_owner(entry.node)))) : element_name(entry.node)
    Any[(isempty(name) ? () : (small(name, seen ? C_TEXT : C_FADED, size=13px),))...,
        (badge(b, seen) for b in badges(entry.node))...]
  end
  # A row that's too long for the panel is cut off at the panel's edge. Its guides keep their width.
  row = Row(width(grow=GrowType.Grow), height(ROW_HEIGHT), padding(0px, 10px, 0px, 8px),
            background(fill), Alignment.Center, clip=true,
    (guide() for _ in 1:entry.depth)...,
    Row(child_gap=7px, Alignment.Center, marker, label...))
  row, marker
end

# --- details ------------------------------------------------------------------

colour_text(c::Colorant) = alpha(c) == 0 ? "none" : "#" * hex(c)
px_text(l) = "$(round(Int, convert(px, l).value))"
enum_text(x) = lowercase(last(split(string(x), '.')))

"A sizing rule written the way you'd pass it to width() or height()"
sizing_text(d::Dimension) = begin
  base = d.preferred != 0px ? "$(px_text(d.preferred))px" :
         d.percent > 0 ? "$(round(Int, 100d.percent))%" :
         d.grow == GrowType.Grow ? "grow" : "fit"
  limits = String[]
  d.min > 0px && push!(limits, "min $(px_text(d.min))")
  isfinite(convert(px, d.max).value) && push!(limits, "max $(px_text(d.max))")
  isempty(limits) ? base : "$base ($(join(limits, ", ")))"
end

box_text(node) = "{ x: $(round(Int, node.left.value)), y: $(round(Int, node.top.value)), " *
                 "width: $(round(Int, node.width.value)), height: $(round(Int, node.height.value)) }"

padding_text(p) = allequal((p.top, p.right, p.bottom, p.left)) ? px_text(p.top) :
  "{ top: $(px_text(p.top)), right: $(px_text(p.right)), bottom: $(px_text(p.bottom)), left: $(px_text(p.left)) }"

side_text(s) = "$(px_text(s.width))px"
border_text(b) = allequal(values(b)) ? side_text(b.top) :
  join(("$(name) $(side_text(s))" for (name, s) in zip(("top", "right", "bottom", "left"), values(b)) if !isempty(s)), ", ")

direction_text(::Row) = "left to right"
direction_text(::Column) = "top to bottom"
direction_text(::Scroll) = "scrolls vertically"
direction_text(::Stack) = "on top of each other"
direction_text(::Container) = "one child"

swatch(c) = Row(child_gap=6px, Alignment.Center,
  Box(width(12px), height(12px), radius(2px), background(c), border(1px, :solid, C_LINE)),
  small(colour_text(c)))

field(label, value::AbstractString) = field(label, Text(value, size=12px, family=FONT, color=C_TEXT, lineheight=1.3em))
field(label, value) = Column(width(grow=GrowType.Grow), child_gap=6px, Alignment.Start,
  small(label, C_DIM, size=11px), value)

fields(node::ConcreteRect) = begin
  ui = node.from
  out = Any[field("Bounding box", box_text(node)),
            field("Layout direction", direction_text(ui)),
            field("Sizing", "width: $(sizing_text(ui.width)), height: $(sizing_text(ui.height))")]
  p = ui.padding
  all(iszero, (p.top.value, p.right.value, p.bottom.value, p.left.value)) || push!(out, field("Padding", padding_text(p)))
  ui.child_gap > 0px && push!(out, field("Child gap", px_text(ui.child_gap)))
  push!(out, field("Alignment", "align: $(enum_text(ui.align)), justify: $(enum_text(ui.justify))"))
  alpha(ui.background.color) > 0 && push!(out, field("Background", swatch(ui.background.color)))
  b = ui.border
  if !isempty(b)
    drawn = first(s for s in values(b) if !isempty(s))
    push!(out, field("Border", Row(child_gap=8px, Alignment.Center, small(border_text(b)), swatch(drawn.color))))
  end
  isempty(b.between) || push!(out, field("Between children", Row(child_gap=8px, Alignment.Center,
                                                                  small(side_text(b.between)), swatch(b.between.color))))
  ui.radius.tl > 0px && push!(out, field("Corner radius", px_text(ui.radius.tl)))
  ui isa Image && push!(out, field("Source", basename(ui.src)))
  ui isa Wedge && push!(out, field("Slice", "radius $(ui.inner)–$(ui.outer), $(round(ui.sweep, digits=1))° wide, starting at $(round(ui.start, digits=1))°"))
  ui isa Scroll && push!(out, field("Scroll offset", "$(px_text(ui.offset)) of $(px_text(max(0px, ui.content_height - node.height)))"))
  out
end

"What a field of a semantic node holds, in a few words"
value_text(x::Union{Number,Symbol,Nothing,Bool,Enum}) = repr(x)
value_text(x::AbstractString) = repr(preview(x, 60))
value_text(x::Union{Tuple,NamedTuple}) = preview(repr(x), 60)
value_text(x::Union{AbstractArray,AbstractDict,AbstractSet}) = "$(nameof(typeof(x))) of $(length(x))"
value_text(x) = string(nameof(typeof(x)))

const TREE_FIELDS = (:parent, :firstchild, :nextsibling, :prevsibling, :stale)

"The fields of the semantic node that made `node`, and the box its element got"
semantic_fields(node::ConcreteRect) = begin
  owner = semantic_owner(node)
  Any[field("Bounding box", box_text(node)),
      field("Drawn as", kind(node) * (isempty(node.from.name) ? "" : " named $(repr(node.from.name))")),
      (field(string(f), value_text(getfield(owner, f))) for f in fieldnames(typeof(owner)) if !(f in TREE_FIELDS))...]
end

fields(node::ConcreteText) = begin
  t = node.from
  [field("Bounding box", box_text(node)),
   field("Content", repr(preview(t.content, 80))),
   field("Font", strip("$(t.family) $(t.subfamily)") * ", $(px_text(t.size))px"),
   field("Lines", "$(length(node.lines)) ($(enum_text(t.wrap)) wrapping)"),
   field("Colour", swatch(t.color))]
end

function details(node, seen, semantic=false)
  semantic &= node isa ConcreteRect && semantic_owner(node) !== nothing
  title = node === nothing ? "" : semantic ? string(nameof(typeof(semantic_owner(node)))) :
          String(strip(element_name(node) * " " * kind(node)))
  header = Row(width(grow=GrowType.Grow), height(30px), padding(12px, 0px), background(C_HEADER),
               border(1px, :solid, C_LINE)[:top, :bottom],
    Box(small(semantic ? "Semantic node" : "Layout config", size=13px)),
    Box(width(grow=GrowType.Grow)),
    Box(small(title, C_DIM)))
  body = node === nothing ?
    Column(width(grow=GrowType.Grow), padding(12px), Alignment.Start,
      Text("Click a row to see how its element was sized. Or click the pick button at the top left, then an element in the app.",
           size=12px, family=FONT, color=C_DIM, lineheight=1.4em)) :
    Column(width(grow=GrowType.Grow), padding(12px), child_gap=12px, Alignment.Start,
      (seen ? () : (field("In view", "No. It's scrolled or clipped out of view."),))...,
      (semantic ? semantic_fields(node) : fields(node))...)
  Column(width(grow=GrowType.Grow), Alignment.Start, background(C_PANEL), header, body)
end

# --- the panel ------------------------------------------------------------------

"""
Build the panel, showing only the rows that are scrolled into view. `marked` is
the element whose row gets the hover colour, and `shown` is the one whose layout
config is listed.
"""
function panel(ins::LayoutInspector, entries, marked, pinned, shown, areas)
  inview(node) = get(areas, node, nothing) !== nothing
  first_row = clamp(floor(Int, ins.scroll.offset / ROW_HEIGHT) + 1, 1, length(entries))
  visible = ceil(Int, max(ins.viewport, 400px) / ROW_HEIGHT) + 2
  last_row = min(length(entries), first_row + visible)
  rows = Any[Box(width(grow=GrowType.Grow), height((first_row - 1) * ROW_HEIGHT))]
  owners = IdDict{Any,Any}()
  for i in first_row:last_row
    entry = entries[i]
    fill = entry.kind == :element && entry.node === marked ? C_HOVER_ROW :
           entry.kind == :element && entry.node === pinned ? C_PINNED_ROW :
           isodd(i) ? C_STRIPE : C_PANEL
    row, marker = tree_row(ins, entry, fill, inview(entry.node))
    owners[row] = (:row, entry.path)
    entry.haschildren && (owners[marker] = (:toggle, entry.path))
    push!(rows, row)
  end
  push!(rows, Box(width(grow=GrowType.Grow), height((length(entries) - last_row) * ROW_HEIGHT)))
  close = Box(width(18px), height(18px), radius(3px), border(1px, :solid, C_CLOSE))
  owners[close] = (:close, Int[])
  # The pick button: a box with a dot in it, lit while the next click picks an element
  lit = ins.picking ? C_HOVER_APP : C_DIM
  pick = Box(width(18px), height(18px), radius(3px), border(1px, :solid, lit), Alignment.Center,
             background(ins.picking ? fade(C_HOVER_APP, 0.25) : RGBA(0, 0, 0, 0)),
    Box(width(6px), height(6px), radius(3px), background(lit)))
  owners[pick] = (:pick, Int[])
  tabs = map((:semantic => "Semantic", :layout => "Layout")) do (view, label)
    on = ins.view == view
    tab = Box(height(grow=GrowType.Grow), padding(12px, 0px), Alignment.Center,
              border(2px, :solid, on ? C_HOVER_APP : RGBA(0, 0, 0, 0))[:bottom],
      small(label, on ? C_TEXT : C_DIM))
    owners[tab] = (:tab, view)
    tab
  end
  geo = Column(width(ins.panel_width), height(grow=GrowType.Grow), background(C_PANEL),
               border(1px, :solid, C_LINE)[:left], Alignment.Start,
    Row(width(grow=GrowType.Grow), height(34px), padding(12px, 0px), background(C_HEADER),
        border(1px, :solid, C_LINE)[:bottom], child_gap=10px,
      pick,
      Box(small(ins.picking ? "Click an element in the app" : "Layout inspector", size=13px)),
      Box(width(grow=GrowType.Grow)),
      close),
    Row(width(grow=GrowType.Grow), height(28px), background(C_HEADER), border(1px, :solid, C_LINE)[:bottom],
        Alignment.Start, tabs...),
    reuse!(ins.scroll, Column(width(grow=GrowType.Grow), Alignment.Start, rows...)),
    details(shown, shown === nothing || inview(shown), ins.view == :semantic))
  geo, owners
end

function draw_tool(ctx, window, ins::LayoutInspector, scene::ConcreteRect)
  w, h = window.size
  app_w = w - ins.panel_width
  mouse = window.mouse
  # The element to highlight: the row under the cursor in the panel or, while
  # picking, the element under it in the app
  ins.hovered = if mouse[1] < app_w
    ins.picking ? deepest_at(scene, mouse) : nothing
  else
    i = findfirst(((rect, _),) -> inside(rect, mouse), ins.rows)
    i === nothing ? nothing : follow(scene, ins.rows[i][2])
  end
  pinned = isempty(ins.selected) ? nothing : follow(scene, ins.selected)
  # The Semantic tab shows the semantic node that an element belongs to
  ins.view == :semantic && (ins.hovered = owned(ins.hovered); pinned = owned(pinned))
  areas = visible_areas(scene, app_w, h)
  # Only the part you can see gets highlighted, so an element scrolled out of
  # view doesn't paint over the header or the panel
  for (node, colour) in ((pinned, C_SELECTED), (ins.hovered, C_HOVER_APP))
    node === nothing && continue
    area = get(areas, node, nothing)
    area === nothing && continue
    l, t, r, b = area
    rounded_rectangle(ctx, l, t, r - l, b - t, 0px, background=colour)
  end
  entries = inspector_entries(ins, scene)
  row = ins.hovered === nothing ? nothing : row_index(entries, ins.hovered)
  # Hovering the app scrolls the tree to the hovered element's row. Hovering
  # the tree itself leaves it where it is, or it would jump under the cursor.
  row !== nothing && mouse[1] < app_w && reveal!(ins, row, length(entries))
  if ins.reveal
    ins.reveal = false
    chosen = pinned === nothing ? nothing : row_index(entries, pinned)
    chosen === nothing || reveal!(ins, chosen, length(entries))
  end
  marked = row === nothing ? nothing : entries[row].node
  # The layout config stays on the selected element. While picking it follows the cursor.
  shown = ins.picking && ins.hovered !== nothing ? ins.hovered : pinned
  geo, owners = panel(ins, entries, marked, pinned, shown, areas)
  concrete = describe(geo, (ins.panel_width, h))
  offset!(concrete, app_w, 0px)
  draw(ctx, concrete.size, concrete)
  # Remember where everything landed so the mouse can find it next time
  tree = nothing
  # A −/+ box that's scrolled half out of the tree doesn't get its symbol
  shows(tree, box) = tree !== nothing && tree.top <= box.top && box.top + box.height <= tree.top + tree.height
  empty!(ins.rows); empty!(ins.toggles); empty!(ins.tabs); ins.close = nothing; ins.pick = nothing
  for (node, _) in flatten(concrete)
    node isa ConcreteRect || continue
    node.from === ins.scroll && (ins.viewport = node.height; tree = node)
    target = get(owners, node.from, nothing)
    target === nothing && continue
    what, path = target
    what == :row && push!(ins.rows, (node, path))
    what == :toggle && (push!(ins.toggles, (node, path)); shows(tree, node) && symbol(ctx, node, path in ins.collapsed ? :plus : :minus))
    what == :tab && push!(ins.tabs, (node, path))
    what == :close && (ins.close = node; symbol(ctx, node, :cross, 3.5px))
    what == :pick && (ins.pick = node)
  end
end

in_panel(ins, window) = window.mouse[1] >= window.size[1] - ins.panel_width

# While picking, the app doesn't hear about the mouse
tool_input(ins::LayoutInspector, window, e::MouseMove) = in_panel(ins, window) || ins.picking || ins.swallow
tool_input(ins::LayoutInspector, window, ::KeyRelease{Keys.mouse_left}) = (was = ins.swallow; ins.swallow = false; was)
tool_input(ins::LayoutInspector, window, ::KeyPress{Keys.escape}) = (was = ins.picking; ins.picking = false; was)
tool_input(ins::LayoutInspector, window, delta::Vec2) = begin
  in_panel(ins, window) || return false
  max_offset = max(0px, ins.scroll.content_height - ins.viewport)
  ins.scroll.offset = clamp(ins.scroll.offset - delta[2] * 30, 0px, max_offset)
  true
end
tool_input(ins::LayoutInspector, window, ::KeyPress{Keys.mouse_left}) = begin
  mouse = window.mouse
  if !in_panel(ins, window)
    ins.picking || return false
    # The click picks the element under it, and the app never sees it
    scene = get(_scenes, objectid(window), nothing)
    node = scene === nothing ? nothing : deepest_at(scene, mouse)
    ins.view == :semantic && (node = owned(node))
    node === nothing || select!(ins, path_to(scene, node))
    ins.picking = false
    ins.swallow = true
    return true
  end
  if ins.pick !== nothing && inside(ins.pick, mouse)
    ins.picking = !ins.picking
    return true
  end
  if ins.close !== nothing && inside(ins.close, mouse)
    clear_tool!(window)
    return true
  end
  i = findfirst(((rect, _),) -> inside(rect, mouse), ins.tabs)
  if i !== nothing
    ins.view = ins.tabs[i][2]
    ins.scroll.offset = 0px
    ins.reveal = true
    return true
  end
  # The −/+ box collapses or expands an element
  i = findfirst(((rect, _),) -> inside(rect, mouse), ins.toggles)
  if i !== nothing
    path = ins.toggles[i][2]
    path in ins.collapsed ? delete!(ins.collapsed, path) : push!(ins.collapsed, path)
    return true
  end
  # Anywhere else on a row selects that element
  i = findfirst(((rect, _),) -> inside(rect, mouse), ins.rows)
  i === nothing && return true
  path = ins.rows[i][2]
  ins.selected = ins.selected == path ? Int[] : path
  true
end
tool_input(ins::LayoutInspector, window, e) = false

export LayoutInspector, toggle_inspector!
