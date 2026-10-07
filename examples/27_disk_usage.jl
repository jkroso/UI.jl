# Disk Usage
#
# Shows what's taking up space on your disk as a sunburst. The folder you're
# looking at is in the middle, and each ring around it is one level deeper.
# Each slice's angle is its share of the folder it's in. It reads the real
# files on your disk, and it never changes or deletes them.
#
# Give it a folder to scan, or it scans your home folder:
#
#     julia examples/27_disk_usage.jl ~/Library
#
# It's light or dark to match your Mac. Add `--dark` or `--light` to choose one.
#
# Things to try:
#   - Hover a slice, or a row in the list, to see how big it is.
#   - Click a folder's slice or row to zoom into it. Click the middle circle, or
#     press esc or ⌘↑, to zoom out. Click a folder in the path at the top to go
#     straight back to it.
#   - Right-click a slice or a row to show it in Finder or to scan it again.
#   - ⌘R scans the folder in the middle again, e.g. after you delete files in Finder.
#   - Drop a folder on the window to scan that folder instead.
#   - ⌘⌥I opens the layout inspector.
#
# The rings fill in while the scan runs. Worker threads read the folders, and
# each frame adds what they've found. Start Julia with more threads to scan
# faster:
#
#     julia -t auto examples/27_disk_usage.jl
#
# Files and folders too small to see are grouped into one grey slice for each
# folder.
#
# The example uses these UI.jl features: `Wedge`, which draws a slice of a ring
# and only takes the cursor where it's drawn, a `Stack` to put the slices in one
# box, `Scroll` with `reuse!`, `ishovered`, `show_menu!`, `dark_mode`, and
# `hide_titlebar!` with `drag_window!` for a window without a title bar.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" measure_text
@use "github.com/jkroso/MiniFB.jl"... onfiledrop
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/abstract" SemanticUI WrapMode describe reuse! window_of focus
@use "../Interface/draw" ui draw ishovered cursor hittest viewport show_menu! open_url
@use "../Interface/fonts" skia_font
@use "../Interface/inspector" toggle_inspector!
@use "../Interface/window" hide_titlebar! drag_window! dark_mode set_dark!
@use "../Interface/Semantic/Icon" Icon
@use "./disk_usage/scan" Item Scan step! stop! running elapsed sorted lineage within rescan! path
@use "./finder/system" available_space
@use Colors: @colorant_str, RGB, RGBA, LCHab, Colorant

# --- look --------------------------------------------------------------------

# The macOS system font, when there is one
const FONT = isfile("/System/Library/Fonts/SFNS.ttf") ? ".SF NS" : "Helvetica"

"The colours for one appearance. `use!` copies one into `colours`."
Base.@kwdef mutable struct Palette
  bg::Colorant
  panel::Colorant         # the list down the side, and the status bar
  ink::Colorant           # text
  dim::Colorant           # secondary text
  faint::Colorant         # buttons you can't use yet
  line::Colorant
  hover::Colorant
  button::Colorant
  middle::Colorant        # the circle in the middle of the chart
  middle_hover::Colorant
  small::Colorant         # the slices that group small items
  lightness::Float64      # how light the innermost ring is
  step::Float64           # how much lighter each ring is than the one inside it
end

const LIGHT = Palette(bg=colorant"white", panel=colorant"rgb(247,247,246)", ink=colorant"rgb(38,38,38)",
                      dim=colorant"rgb(128,128,128)", faint=colorant"rgb(190,190,190)", line=colorant"rgb(229,229,229)",
                      hover=colorant"rgb(234,234,233)", button=colorant"white", middle=colorant"rgb(243,243,242)",
                      middle_hover=colorant"rgb(232,232,231)", small=colorant"rgb(196,196,194)",
                      lightness=60, step=5)

const DARK = Palette(bg=colorant"rgb(30,30,30)", panel=colorant"rgb(37,37,37)", ink=colorant"rgb(225,225,225)",
                     dim=colorant"rgb(150,150,150)", faint=colorant"rgb(95,95,95)", line=colorant"rgb(58,58,58)",
                     hover=colorant"rgb(56,56,56)", button=colorant"rgb(50,50,50)", middle=colorant"rgb(42,42,42)",
                     middle_hover=colorant"rgb(54,54,54)", small=colorant"rgb(92,92,92)",
                     lightness=50, step=5)

const colours = deepcopy(LIGHT)

use!(p::Palette) = foreach(n -> setfield!(colours, n, getfield(p, n)), fieldnames(Palette))

const transparent = RGBA(0, 0, 0, 0)

# As tall as a title bar, so the window's close, minimise and zoom buttons sit
# in line with the toolbar's own
const TOOLBAR_H = 32px
const STATUS_H  = 28px
const LIST_W    = 360px
const ROW       = 26px
const NAME_W    = 170px   # room for a name in the list
const MAX_ROWS  = 200     # the list groups the rest into one row

# The chart's sizes are fractions of its radius
const MIDDLE    = 0.27    # the radius of the circle in the middle
const RINGS     = 5       # how many rings show at once
const EDGE      = 0.985   # where the last ring ends
const THICK     = (EDGE - MIDDLE) / RINGS
const MIN_SWEEP = 0.8     # degrees. Thinner slices are grouped together.
const ZOOM_TIME = 0.45    # seconds
const SCAN_TIME = 0.025   # the most time each frame spends adding what the scan found

const grow = GrowType.Grow
fixed(w) = width(preferred=w, grow=GrowType.None)

label(s, size=13px; color=colours.ink, weight="", align=TextAlign.Left) =
  Text(s, size=size, family=FONT, subfamily=weight, color=color, wrap=WrapMode.none, align=align)

text_width(s, size) = px(measure_text(skia_font(FONT, size, ""), s)[1])

const _fitted = Dict{Tuple{String,Any,px},String}()

"`name`, shortened in the middle until it fits in `w`, so you can still see the extension"
fit(name, w; size=13px) = get!(_fitted, (name, size, w)) do
  text_width(name, size) <= w && return name
  chars = collect(name)
  lo, hi, best = 1, length(chars) - 1, "…"
  while lo <= hi
    keep = (lo + hi) ÷ 2
    head = cld(keep, 2)
    s = String(chars[1:head]) * "…" * String(chars[end-(keep-head)+1:end])
    text_width(s, size) <= w ? (best = s; lo = keep + 1) : (hi = keep - 1)
  end
  best
end

size_text(n) =
  n < 1000 ? "$n bytes" :
  n < 1_000_000 ? "$(round(Int, n / 1e3)) KB" :
  n < 1_000_000_000 ? "$(digits3(n / 1e6)) MB" :
  n < 1_000_000_000_000 ? "$(digits3(n / 1e9)) GB" :
                          "$(digits3(n / 1e12)) TB"

"`x` to 3 significant digits, without a trailing \".0\""
digits3(x) = (r = round(x, sigdigits=3); r == round(r) ? string(round(Int, r)) : string(r))

commas(n) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")
files_text(n) = n == 1 ? "1 file" : "$(commas(n)) files"

share_text(part, whole) = begin
  whole > 0 || return ""
  p = 100 * part / whole
  p < 0.5 ? "<1%" : "$(round(Int, p))%"
end

"The name to show for an item. The folder the scan started at shows its path."
name(item::Item) = begin
  item.parent === nothing || return item.name
  home = homedir()
  item.name == home || startswith(item.name, home * "/") ? "~" * item.name[length(home)+1:end] : item.name
end

"The colour of a slice with hue `hue` on ring `ring`. Each ring out is lighter."
slice_colour(hue, ring, folder, hover) = begin
  l = colours.lightness + colours.step * (max(ring, 1) - 1) + (hover ? 9 : 0)
  c = folder ? 48 - 3 * (max(ring, 1) - 1) : 18
  rgb = convert(RGB{Float64}, LCHab(clamp(l, 0, 100), c, hue + 30))
  RGB(clamp(rgb.r, 0, 1), clamp(rgb.g, 0, 1), clamp(rgb.b, 0, 1))
end

"The colour of a slice that groups small items"
small_colour(ring, hover) = begin
  c = convert(RGB{Float64}, colours.small)
  k = 0.03 * (max(ring, 1) - 1) + (hover ? 0.08 : 0)
  RGB(min(1, c.r + k), min(1, c.g + k), min(1, c.b + k))
end

# --- the app -------------------------------------------------------------------

"""
What the chart shows. `anchor` is in the middle, the part of its rings from
`from` to `to` degrees is spread round the whole circle, and the rings are
pushed in by `depth`. A zoom moves smoothly from one view to another.
"""
struct View
  anchor::Item
  from::Float64
  to::Float64
  depth::Float64
end

View(item::Item) = View(item, 0.0, 360.0, 0.0)

"A zoom that's under way, between `anchor` and the folder `inner` inside it"
struct Zoom
  anchor::Item
  inner::Item
  inward::Bool
  started::Float64
end

@def mutable struct DiskUsage <: SemanticUI
  scan::Any = nothing
  zoom::Any = nothing                     # the folder in the middle of the chart
  moving::Any = nothing                   # a Zoom, while one is under way
  # The slice or row under the cursor, and its key: an Item, or (:small, folder)
  # for the slice or row that groups the small items in a folder
  pointed::Any = nothing
  hover::Any = nothing
  frame::Int = 0
  # Nodes for slices, rows and path parts, kept so hover and clicks can find them
  slices::IdDict{Any,Any} = IdDict{Any,Any}()
  rows::IdDict{Any,Any} = IdDict{Any,Any}()
  crumbs::IdDict{Any,Any} = IdDict{Any,Any}()
  middle::Any = nothing
  titlebar::Any = nothing
  buttons::Dict{Symbol,Any} = Dict{Symbol,Any}()
  list::Scroll = Scroll(width(grow=grow), height(grow=grow), name="List")
  free::Tuple{Float64,Int64} = (0.0, 0)  # when the free space was last read, and how much there was
  appearance::Symbol = :system           # :system follows the Mac. :light and :dark don't.
  dark::Union{Nothing,Bool} = nothing
  # The size to lay out at when the app isn't in a window, e.g. for a PNG
  size::Tuple{px,px} = (1100px, 720px)
end

"One slice of the chart. `key` is its Item, or (:small, folder) for a slice of small items."
@def mutable struct Slice <: SemanticUI
  key::Any = nothing
  item::Any = nothing                     # its Item, or the folder for a slice of small items
  count::Int = 1                          # how many items it stands for
  bytes::Int64 = 0
  inner::Float64 = 0.0
  outer::Float64 = 1.0
  start::Float64 = 0.0
  sweep::Float64 = 0.0
  colour::Colorant = transparent
  base::Colorant = transparent            # its colour when it isn't under the cursor
  frame::Int = 0                          # the last frame it was drawn in
end

"A row in the list. Its fields mean the same as a Slice's."
@def mutable struct ListRow <: SemanticUI
  key::Any = nothing
  item::Any = nothing
  count::Int = 1
  bytes::Int64 = 0
end

"The circle in the middle. Clicking it zooms out."
@def mutable struct Middle <: SemanticUI end

"A folder in the path at the top"
@def mutable struct Crumb <: SemanticUI
  item::Any = nothing
end

"The toolbar. The window has no title bar, so dragging the toolbar's empty parts moves it."
@def mutable struct TitleBar <: SemanticUI end

@def mutable struct ToolButton <: SemanticUI
  action::Symbol = :up
  icon::String = ""
  text::String = ""
end

app_of(node) = begin
  while !(node isa DiskUsage)
    node = node.parent
  end
  node
end

"A node that belongs to `a` and is kept for as long as `a` is"
own!(a, node) = (node.parent === nothing && setfield!(node, :parent, a); node)

DiskUsage(scan::Scan; kwargs...) = begin
  a = DiskUsage(; scan=scan, zoom=scan.root, kwargs...)
  a.middle = own!(a, Middle())
  a.titlebar = own!(a, TitleBar())
  a.buttons[:up] = own!(a, ToolButton(action=:up, icon="arrow-up"))
  a.buttons[:rescan] = own!(a, ToolButton(action=:rescan, icon="arrow-clockwise", text="Scan Again"))
  a
end

"Start again on another folder"
scan!(a::DiskUsage, dir) = begin
  stop!(a.scan)
  a.scan = Scan(dir)
  a.zoom = a.scan.root
  a.moving = nothing
  a.free = (0.0, 0)
  forget!(a)
end

"Drop the nodes made for items, after the items they show have changed"
forget!(a) = (empty!(a.slices); empty!(a.rows); empty!(a.crumbs); a)

window_size(a) = something(viewport(a), a.size)

# --- zooming -------------------------------------------------------------------

ease(t) = t < 0.5 ? 4t^3 : 1 - (-2t + 2)^3 / 2

"Where `item` sits in a chart of `anchor`: its first and last angle, and how many rings out it is"
placement(anchor::Item, item::Item) = begin
  item === anchor && return (0.0, 360.0, 0)
  a0, a1, depth = placement(anchor, item.parent)
  folder = item.parent
  scale = (a1 - a0) / max(folder.bytes, 1)
  before = 0
  for c in sorted(folder)
    c === item && break
    before += c.bytes
  end
  (a0 + before * scale, a0 + (before + item.bytes) * scale, depth + 1)
end

"Put `folder` in the middle of the chart, moving there smoothly when it's above or below the folder there now"
zoom!(a::DiskUsage, folder::Item) = begin
  (folder.folder && folder !== a.zoom) || return
  from = a.zoom
  a.moving = within(folder, from) ? Zoom(from, folder, true, time()) :
             within(from, folder) ? Zoom(folder, from, false, time()) : nothing
  a.zoom = folder
  a.list.offset = 0px
end

zoom_out!(a::DiskUsage) = a.zoom.parent === nothing || zoom!(a, a.zoom.parent)

"The view to draw this frame, part way through a zoom if one is under way"
view!(a::DiskUsage) = begin
  z = a.moving
  z === nothing && return View(a.zoom)
  t = (time() - z.started) / ZOOM_TIME
  if t >= 1 || !within(z.inner, z.anchor)
    a.moving = nothing
    return View(a.zoom)
  end
  k = z.inward ? ease(t) : 1 - ease(t)
  a0, a1, depth = placement(z.anchor, z.inner)
  View(z.anchor, a0 * k, 360 + (a1 - 360) * k, depth * k)
end

# --- the chart -----------------------------------------------------------------

"A Slice for each part of the view's folder tree that's big enough to see"
slices(a::DiskUsage, v::View) = begin
  out = Slice[]
  k = 360 / (v.to - v.from)
  screen(angle) = (angle - v.from) * k
  visit(folder, depth, a0, a1, hue, mid) = begin
    folder.bytes > 0 || return
    ring = depth - v.depth
    inner = MIDDLE + (ring - 1) * THICK
    inner < EDGE || return
    outer = min(inner + THICK, EDGE)
    inner = max(inner, MIDDLE)
    shown = outer - inner > 0.002
    scale = (a1 - a0) / folder.bytes
    kids = sorted(folder)
    at = a0
    for (i, child) in enumerate(kids)
      next = at + child.bytes * scale
      if (next - at) * k < MIN_SWEEP
        # The rest are smaller still, so they share one slice
        rest = sum(c -> c.bytes, @view(kids[i:end]))
        shown && add!(out, a, (:small, folder), folder, length(kids) - i + 1, rest,
                      screen(at), screen(at + rest * scale), inner, outer, ring, hue)
        break
      end
      s0, s1 = screen(at), screen(next)
      s0 >= 360 && break
      if s1 > 0
        # Slices on the first ring take their hue from where they are round the
        # circle. Further out they take their folder's, so each folder's
        # contents look alike. Between the two during a zoom, they mix.
        m = (s0 + s1) / 2
        h = mix(hue + 0.25 * (m - mid), m, clamp(2 - ring, 0, 1))
        shown && add!(out, a, child, child, 1, child.bytes, s0, s1, inner, outer, ring, h)
        child.folder && visit(child, depth + 1, at, next, h, m)
      end
      at = next
    end
  end
  visit(v.anchor, 1, 0.0, 360.0, 0.0, 0.0)
  out
end

"The hue `w` of the way from hue `a` to hue `b`, going the short way round"
mix(a, b, w) = a + w * (mod(b - a + 180, 360) - 180)

add!(out, a::DiskUsage, key, item, count, bytes, s0, s1, inner, outer, ring, hue) = begin
  s0, s1 = max(s0, 0.0), min(s1, 360.0)
  s1 > s0 || return
  s = get!(() -> own!(a, Slice()), a.slices, key)
  s.key, s.item, s.count, s.bytes = key, item, count, bytes
  s.inner, s.outer, s.start, s.sweep = inner, outer, s0, s1 - s0
  hover = a.hover === key
  colour(hover) = key isa Item ? slice_colour(hue, ring, item.folder, hover) : small_colour(ring, hover)
  s.base = colour(false)
  s.colour = hover ? colour(true) : s.base
  s.frame = a.frame
  push!(out, s)
end

describe(s::Slice) =
  Wedge(width(grow=grow), height(grow=grow), inner=s.inner, outer=s.outer, start=s.start, sweep=s.sweep,
        background(s.colour), border(1px, :solid, colours.bg))

describe(m::Middle) = begin
  a = app_of(m)
  can_zoom_out = a.zoom.parent !== nothing
  Wedge(width(grow=grow), height(grow=grow), outer=MIDDLE,
        background(can_zoom_out && ishovered(m) ? colours.middle_hover : colours.middle),
    summary(a))
end

"The radius of the chart, worked out from the window's size"
chart_radius(a) = begin
  w, h = window_size(a)
  min(w - LIST_W - 48px, h - TOOLBAR_H - STATUS_H - 48px) / 2
end

"What the middle circle says: about the item under the cursor, or else the folder in the middle"
summary(a::DiskUsage) = begin
  room = max(60px, chart_radius(a) * MIDDLE * 1.6)
  p = a.pointed
  title, bytes, details = if p === nothing
    name(a.zoom), a.zoom.bytes, [files_text(a.zoom.files)]
  elseif p.key isa Tuple
    "$(commas(p.count)) smaller items", p.bytes, ["in " * basename(path(p.item))]
  else
    item = p.item
    share = share_text(item.bytes, a.zoom.bytes) * " of " * basename(path(a.zoom))
    name(item), item.bytes, item.folder ? [files_text(item.files), share] : [share]
  end
  Column(child_gap=8px, Alignment.Center,
    label(fit(title, room, size=13px), 13px, weight="Semibold", align=TextAlign.Center),
    label(size_text(bytes), 22px, weight="Semibold", align=TextAlign.Center),
    (label(fit(d, room, size=11px), 11px, color=colours.dim, align=TextAlign.Center) for d in details)...)
end

onkey(m::Middle, ::KeyPress{Keys.mouse_left}) = zoom_out!(app_of(m))
cursor(m::Middle) = app_of(m).zoom.parent === nothing ? nothing : :hand

"The folder a click on a slice or a row zooms into"
target(node) = node.key isa Tuple ? node.item : node.item.folder ? node.item : nothing

onkey(s::Union{Slice,ListRow}, ::KeyPress{Keys.mouse_left}) = begin
  t = target(s)
  t === nothing || zoom!(app_of(s), t)
end
onkey(s::Union{Slice,ListRow}, ::KeyPress{Keys.mouse_right}) = item_menu(app_of(s), s.item)
cursor(s::Union{Slice,ListRow}) = target(s) === nothing ? nothing : :hand

"Show in Finder, open, or scan again"
item_menu(a::DiskUsage, item::Item) = begin
  w = window_of(a)
  w === nothing && return
  p = path(item)
  actions = Pair{String,Function}["Show in Finder" => () -> reveal(p)]
  item.folder || push!(actions, "Open" => () -> open_url(p))
  item.folder && push!(actions, "Scan Again" => () -> rescan_item!(a, item))
  show_menu!(w, first.(actions), w.mouse..., 160px, onselect=i -> i > 0 && last(actions[i])())
end

reveal(p) = Sys.isapple() ? run(`open -R $p`, wait=false) : open_url(dirname(p))

"Read `folder` again. If the middle of the chart is inside it, `folder` moves to the middle."
rescan_item!(a::DiskUsage, folder::Item) = begin
  within(a.zoom, folder) && (a.zoom = folder; a.moving = nothing)
  rescan!(a.scan, folder)
  forget!(a)
end

chart(a::DiskUsage, parts) =
  Box(width(grow=grow), height(grow=grow), padding(24px), name="Chart",
    Stack(width(grow=grow), height(grow=grow), name="Sunburst", parts..., a.middle))

# --- the list ------------------------------------------------------------------

"Rows for the folder in the middle: its biggest items, then one row for the rest"
rows(a::DiskUsage) = begin
  folder = a.zoom
  kids = sorted(folder)
  out = ListRow[]
  for child in Iterators.take(kids, MAX_ROWS)
    r = get!(() -> own!(a, ListRow()), a.rows, child)
    r.key, r.item, r.count, r.bytes = child, child, 1, child.bytes
    push!(out, r)
  end
  if length(kids) > MAX_ROWS
    key = (:small, folder)
    r = get!(() -> own!(a, ListRow()), a.rows, key)
    r.key, r.item, r.count = key, folder, length(kids) - MAX_ROWS
    r.bytes = sum(c -> c.bytes, @view(kids[MAX_ROWS+1:end]))
    push!(out, r)
  end
  out
end

"The colour a row's icon takes from its slice, or grey when the slice is too small to draw"
row_colour(a, r::ListRow) = begin
  s = get(a.slices, r.key, nothing)
  s === nothing || s.frame != a.frame ? colours.faint : s.base
end

describe(r::ListRow) = begin
  a = app_of(r)
  small = r.key isa Tuple
  icon = small ? "three-dots" : r.item.folder ? "folder-fill" : "file-earmark-fill"
  title = small ? "$(commas(r.count)) more items" : r.item.name
  Row(width(grow=grow), height(ROW), padding(14px, 0px), child_gap=10px, Alignment.Center,
      background(a.hover === r.key ? colours.hover : transparent),
    Icon(icon, size=14px, color=row_colour(a, r)),
    label(fit(title, NAME_W)),
    Box(width(grow=grow)),
    Box(fixed(40px), label(share_text(r.bytes, a.zoom.bytes), 12px, color=colours.dim, align=TextAlign.Right)),
    Box(fixed(72px), label(size_text(r.bytes), 12px, align=TextAlign.Right)))
end

list_panel(a::DiskUsage) = begin
  folder = a.zoom
  detail = files_text(folder.files) * (folder.denied ? " · couldn't be read" : "")
  body = isempty(folder.children) ?
    Box(width(grow=grow), height(grow=grow), Alignment.Center,
        label(folder.read ? "This folder is empty." : "Not read yet…", color=colours.dim)) :
    reuse!(a.list, Column(width(grow=grow), padding(0px, 0px, 8px, 0px), Alignment.Start, rows(a)...))
  Column(fixed(LIST_W), height(grow=grow), Alignment.Start, background(colours.panel),
         border(1px, :solid, colours.line)[:left], name="List",
    Column(width(grow=grow), padding(14px, 16px), child_gap=8px, Alignment.Start,
           border(1px, :solid, colours.line)[:bottom],
      label(fit(name(folder), LIST_W - 32px, size=15px), 15px, weight="Semibold"),
      label(size_text(folder.bytes) * " · " * detail, 12px, color=colours.dim)),
    body)
end

# --- the toolbar and status bar ----------------------------------------------------

enabled(a, action) = action == :up ? a.zoom.parent !== nothing : true

describe(b::ToolButton) = begin
  a = app_of(b)
  on = enabled(a, b.action)
  ink = on ? colours.ink : colours.faint
  parts = Any[Icon(b.icon, size=13px, color=ink)]
  isempty(b.text) || push!(parts, label(b.text, 12px, color=ink))
  Row(height(24px), padding(isempty(b.text) ? 6px : 9px, 0px), child_gap=5px, radius(6px), Alignment.Center,
      background(on && ishovered(b) ? colours.hover : colours.button), border(1px, :solid, colours.line), parts...)
end

onkey(b::ToolButton, ::KeyPress{Keys.mouse_left}) = begin
  a = app_of(b)
  enabled(a, b.action) || return
  b.action == :up ? zoom_out!(a) : rescan_item!(a, a.zoom)
end
cursor(b::ToolButton) = enabled(app_of(b), b.action) ? :hand : nothing

describe(c::Crumb) = begin
  a = app_of(c)
  here = c.item === a.zoom
  Row(height(22px), padding(7px, 0px), radius(5px), Alignment.Center,
      background(!here && ishovered(c) ? colours.hover : transparent),
    label(fit(name(c.item), 200px), 13px, color=here ? colours.ink : colours.dim, weight=here ? "Semibold" : ""))
end

onkey(c::Crumb, ::KeyPress{Keys.mouse_left}) = zoom!(app_of(c), c.item)
cursor(c::Crumb) = c.item === app_of(c).zoom ? nothing : :hand

"The folders from the one scanned down to the one in the middle. Long paths lose their middle."
crumbs(a::DiskUsage) = begin
  chain = lineage(a.zoom)
  shown = length(chain) <= 6 ? chain : [chain[1:2]; nothing; chain[end-2:end]]
  parts = Any[]
  for item in shown
    isempty(parts) || push!(parts, Icon("chevron-right", size=10px, color=colours.faint))
    push!(parts, item === nothing ? label("…", color=colours.dim) :
                 get!(() -> own!(a, Crumb(item=item)), a.crumbs, item))
  end
  Row(width(grow=grow), height(grow=grow), child_gap=2px, Alignment.Center, clip=true, parts...)
end

# The window's close, minimise and zoom buttons float over the toolbar's left end
describe(t::TitleBar) = begin
  a = app_of(t)
  Row(width(grow=grow), height(TOOLBAR_H), padding(0px, 8px, 0px, 80px), child_gap=10px, Alignment.Center,
      border(1px, :solid, colours.line)[:bottom], name="Toolbar",
    a.buttons[:up], crumbs(a), a.buttons[:rescan])
end

onkey(t::TitleBar, ::KeyPress{Keys.mouse_left}) = drag_window!(window_of(t))

"Bytes free on the scanned disk, read again every few seconds"
free_space(a::DiskUsage) = begin
  checked, n = a.free
  time() - checked < 5 && return n
  n = try available_space(path(a.scan.root)) catch; 0 end
  a.free = (time(), n)
  n
end

status_bar(a::DiskUsage) = begin
  s = a.scan
  root = s.root
  seconds = round(Int, elapsed(s))
  took = seconds < 1 ? "under a second" : seconds == 1 ? "1 second" : "$seconds seconds"
  left = running(s) ? "Scanning… $(files_text(root.files)), $(size_text(root.bytes)) so far" :
                      "$(files_text(root.files)), $(size_text(root.bytes)). Scanned in $took."
  s.denied > 0 && (left *= " $(commas(s.denied)) $(s.denied == 1 ? "folder" : "folders") couldn't be read.")
  free = free_space(a)
  Row(width(grow=grow), height(STATUS_H), padding(14px, 0px), Alignment.Center, background(colours.panel),
      border(1px, :solid, colours.line)[:top], name="Status",
    label(left, 12px, color=colours.dim),
    Box(width(grow=grow)),
    label(free > 0 ? "$(size_text(free)) free on this disk" : "", 12px, color=colours.dim))
end

# --- the whole window ------------------------------------------------------------

"Pick light or dark colours, and tell the window so its title bar matches"
use_appearance!(a) = begin
  dark = a.appearance == :system ? dark_mode() : a.appearance == :dark
  use!(dark ? DARK : LIGHT)
  win = window_of(a)
  win === nothing || dark === a.dark || set_dark!(win, dark)
  a.dark = dark
end

"The slice or row `node` is part of, or `nothing`"
part_of(node) = begin
  while node !== nothing && !(node isa DiskUsage)
    node isa Union{Slice,ListRow} && return node
    node = node.parent
  end
  nothing
end

describe(a::DiskUsage) = begin
  use_appearance!(a)
  win = window_of(a)
  win === nothing || step!(a.scan, SCAN_TIME)
  within(a.zoom, a.scan.root) || (a.zoom = a.scan.root)
  a.frame += 1
  if win !== nothing
    a.pointed = part_of(hittest(win))
    a.hover = a.pointed === nothing ? nothing : a.pointed.key
  end
  parts = slices(a, view!(a))
  win === nothing || (win.animating = running(a.scan) || a.moving !== nothing)
  Column(width(grow=grow), height(grow=grow), Alignment.Start, background(colours.bg), name="DiskUsage",
    a.titlebar,
    Row(width(grow=grow), height(grow=grow), Alignment.Start,
      chart(a, parts),
      list_panel(a)),
    status_bar(a))
end

onkey(a::DiskUsage, e::KeyPress{K}) where K = begin
  K in (Keys.mouse_left, Keys.mouse_right, Keys.mouse_middle) && return
  w = e.window
  cmd, opt = Keys.cmd in w.keys, Keys.opt in w.keys
  if K == Keys.escape || (cmd && K == Keys.up)
    zoom_out!(a)
  elseif cmd && opt && K == Keys.i
    toggle_inspector!(w)
  elseif cmd && K == Keys.r
    rescan_item!(a, a.zoom)
  end
end

onopen(w::Window) = hide_titlebar!(w)

onfiledrop(w::Window, paths) = begin
  a = w.ui
  dirs = filter(isdir, paths)
  (a isa DiskUsage && !isempty(dirs)) && scan!(a, dirs[1])
end

"""
Scan a folder and open a window to show it. `args` can name the folder, and
`--dark` or `--light` to choose an appearance.
"""
open_disk_usage(args) = begin
  # macOS can pass its own -options to an app it opens, so skip anything with a dash
  folders = filter(a -> !startswith(a, "-"), args)
  dir = isempty(folders) ? homedir() : folders[1]
  isdir(expanduser(dir)) || (println(stderr, "$dir isn't a folder"); exit(1))
  app = DiskUsage(Scan(dir), appearance="--dark" in args ? :dark : "--light" in args ? :light : :system)
  window = Window(app, title="Disk Usage", size=(1100px, 720px))
  focus(app)
  display(window)
end

if abspath(PROGRAM_FILE) == @__FILE__
  open_disk_usage(ARGS)
end
