# Finder
#
# A file browser modelled on the macOS Finder: a sidebar of places, a toolbar
# with back and forward buttons, four ways to view a folder, a path bar and a
# Quick Look panel. It shows the real files on your disk. You can open them,
# and drag them to move or copy them. It never deletes or replaces a file.
#
# Give it a folder to start in, or it starts in your home folder:
#
#     julia examples/26_finder.jl ~/Desktop
#
# It's light or dark to match your Mac, and it switches when you change the
# setting. Add `--dark` or `--light` to choose one.
#
# Things to try:
#   - Switch between the icon, list, column and sunburst views with the toolbar, or ⌘1 to ⌘4.
#   - The sunburst view is the chart from the Disk Usage example. It shows what's
#     using the space in the folder. Hover a slice to see how big it is. Click a
#     folder's slice to go into it, and the middle to go back out. ⌘R reads the
#     folder again.
#   - Click to select. ⌘-click and shift-click select more. Double-click opens.
#   - Use the arrow keys. In the list view, → and ← open and close folders.
#   - Click a column heading in the list view to sort by it.
#   - Press space to Quick Look the selection. Type the start of a name to jump to it.
#   - ⌘[ and ⌘] go back and forward. ⌘↑ goes to the enclosing folder.
#   - ⌘⇧. shows hidden files. ⌘F searches the folder by name. ⌘⌥I opens the layout inspector.
#   - Drag files onto a folder, a sidebar place or the path bar to move them there.
#     Hold ⌥ to copy them instead. ⌘Z moves them back.
#   - Drag across empty space to select the files in the box.
#   - Right-click a file or folder, or control-click it, for a menu. It opens
#     what's selected, Quick Looks it, duplicates it or copies its path.
#
# On macOS the names, kinds and icons come from the system, so they match what
# Finder shows. On other systems the example uses plain names and drawn icons.
#
# The example uses these UI.jl features: a `Stack` to float Quick Look over the
# window, `Scroll` with `scroll_into_view!`, images from memory with
# `register_image`, a `TextInput` with its own look, font weights by name, and
# `hide_titlebar!` with `drag_window!` for a window without a title bar.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl/units" em
@use "github.com/jkroso/MiniFB.jl/skia" measure_text
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/abstract" SemanticUI WrapMode describe reuse! window_of focus add_child!
@use "../Interface/draw" ui draw ishovered cursor open_url viewport hittest
@use "../Interface/fonts" skia_font
@use "../Interface/image" image_aspect
@use "../Interface/inspector" toggle_inspector!
@use "../Interface/save" save_png
@use "../Interface/window" hide_titlebar! drag_window! dark_mode set_dark!
@use "../Interface/Semantic/Icon" Icon
@use "../Interface/Semantic/TextInput" TextInput
@use "./finder/system" file_info file_icon available_space sidebar_volume locale
@use "./27_disk_usage" DiskUsage scan! zoom! rescan_item! busy
@use "./disk_usage/scan" Scan stop! running path => item_path
@use Colors: @colorant_str, RGBA, Colorant
@use InteractiveUtils: clipboard

# --- look --------------------------------------------------------------------

# The macOS system font, when there is one
const FONT = isfile("/System/Library/Fonts/SFNS.ttf") ? ".SF NS" : "Helvetica"

"""
The colours for one appearance. `colours` holds the ones being drawn with, and
`use!` swaps them when the appearance changes.
"""
Base.@kwdef mutable struct Palette
  bg::Colorant          # behind the files
  ink::Colorant         # text
  dim::Colorant         # secondary text, like dates and sizes
  faint::Colorant       # buttons you can't use yet, and path bar arrows
  line::Colorant
  stripe::Colorant      # every second row of the list view
  sidebar::Colorant
  sidebar_on::Colorant  # the sidebar place you're in
  section::Colorant     # sidebar headings
  accent::Colorant      # sidebar icons and the search field's ring
  selected::Colorant
  selected_2::Colorant  # a selection that doesn't have the keyboard
  onsel::Colorant       # text on a selection
  icon_bg::Colorant     # behind a selected icon in the icon view
  capsule::Colorant     # toolbar button groups
  capsule_on::Colorant
  hover::Colorant
  folder::Colorant      # drawn folders, shown while the system's icons load
  backdrop::Colorant    # dims the window behind Quick Look
  panel_line::Colorant  # Quick Look's edge
  drop::Colorant        # the folder that dragged files would land in
  marquee::Colorant     # the box you drag to select files
end

const LIGHT = Palette(bg=colorant"white", ink=colorant"rgb(38,38,38)", dim=colorant"rgb(128,128,128)",
                      faint=colorant"rgb(190,190,190)", line=colorant"rgb(229,229,229)",
                      stripe=colorant"rgb(245,245,245)", sidebar=colorant"rgb(238,237,235)",
                      sidebar_on=colorant"rgb(216,216,214)", section=colorant"rgb(160,159,157)",
                      accent=colorant"rgb(30,119,249)", selected=colorant"rgb(48,98,228)",
                      selected_2=colorant"rgb(220,220,220)", onsel=colorant"white", icon_bg=colorant"rgb(226,226,226)",
                      capsule=colorant"rgb(252,252,252)", capsule_on=colorant"rgb(230,230,230)",
                      hover=colorant"rgb(240,240,240)", folder=colorant"rgb(110,180,235)",
                      backdrop=RGBA(0, 0, 0, 0.25), panel_line=colorant"rgb(200,200,200)",
                      drop=RGBA(30/255, 119/255, 249/255, 0.22), marquee=RGBA(30/255, 119/255, 249/255, 0.15))

const DARK = Palette(bg=colorant"rgb(30,30,30)", ink=colorant"rgb(225,225,225)", dim=colorant"rgb(150,150,150)",
                     faint=colorant"rgb(95,95,95)", line=colorant"rgb(58,58,58)",
                     stripe=colorant"rgb(37,37,37)", sidebar=colorant"rgb(43,42,44)",
                     sidebar_on=colorant"rgb(70,69,72)", section=colorant"rgb(128,127,130)",
                     accent=colorant"rgb(70,150,255)", selected=colorant"rgb(35,90,210)",
                     selected_2=colorant"rgb(65,65,65)", onsel=colorant"white", icon_bg=colorant"rgb(66,66,66)",
                     capsule=colorant"rgb(50,50,50)", capsule_on=colorant"rgb(82,82,82)",
                     hover=colorant"rgb(64,64,64)", folder=colorant"rgb(90,165,230)",
                     backdrop=RGBA(0, 0, 0, 0.45), panel_line=colorant"rgb(75,75,75)",
                     drop=RGBA(70/255, 150/255, 255/255, 0.3), marquee=RGBA(70/255, 150/255, 255/255, 0.2))

const colours = deepcopy(LIGHT)

"Draw with the colours in `p` from now on"
use!(p::Palette) = foreach(n -> setfield!(colours, n, getfield(p, n)), fieldnames(Palette))

const SIDEBAR_W = 180px
const TOOLBAR_H = 52px
const PATHBAR_H = 28px
const HEADER_H  = 28px
const ROW       = 24px   # a row in the list view
const COL_ROW   = 22px   # a row in the column view
const COL_W     = 230px
const PREVIEW_W = 280px
const CELL_W    = 104px  # a file in the icon view
const CELL_H    = 108px
const ICON      = 64px
const INDENT    = 16px
const DATE_W    = 190px
const SIZE_W    = 90px
const KIND_W    = 160px
const GRID_PAD  = 12px

const grow = GrowType.Grow
fixed(w) = width(preferred=w, grow=GrowType.None)

label(s, size=13px; color=colours.ink, weight="") =
  Text(s, size=size, family=FONT, subfamily=weight, color=color, wrap=WrapMode.none)

# --- measuring names ---------------------------------------------------------

text_width(s, size, weight="") = px(measure_text(skia_font(FONT, size, weight), s)[1])

const _fitted = Dict{Tuple{String,Any,px},String}()

"""
`name`, shortened with an ellipsis in the middle until it fits in `w`. Finder
cuts names this way so you can still see the extension.
"""
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

"A name broken into at most two centred lines for the icon view"
cell_name(name, w=CELL_W - 12px; size=12px) = begin
  text_width(name, size) <= w && return name
  lines = String[]
  line = ""
  for word in split(name, ' ')
    trial = isempty(line) ? word : "$line $word"
    if text_width(trial, size) <= w || isempty(line)
      line = trial
    else
      push!(lines, line)
      line = word
    end
  end
  push!(lines, line)
  length(lines) == 1 && return fit(lines[1], w, size=size)
  first_line = fit(lines[1], w, size=size)
  rest = fit(join(lines[2:end], ' '), w, size=size)
  "$first_line\n$rest"
end

# --- files -------------------------------------------------------------------

"One file or folder, read when its folder is listed"
struct Entry
  path::String
  name::String       # the name Finder shows
  folder::Bool       # a folder you can look inside. Apps and other packages aren't.
  package::Bool
  hidden::Bool
  size::Int64        # -1 for folders
  modified::Float64
  kind::String
end

"A folder's contents, and the folder's modification time when they were read"
struct Listing
  mtime::Float64
  entries::Vector{Entry}
  error::String
end

const _listings = Dict{String,Listing}()

"The contents of `dir`. It's read again only when files are added or removed."
listing(dir) = begin
  m = try mtime(dir) catch; -1.0 end
  cached = get(_listings, dir, nothing)
  cached !== nothing && cached.mtime == m && return cached
  _listings[dir] = read_listing(dir, m)
end

read_listing(dir, m) = try
  entries = Entry[]
  for name in readdir(dir)
    path = joinpath(dir, name)
    st = try stat(path) catch; continue end
    isdir_ = isdir(st)
    info = file_info(path, isdir_)
    push!(entries, Entry(path, info.name, isdir_ && !info.package, info.package, info.hidden,
                         isdir_ ? -1 : st.size, st.mtime, info.kind))
  end
  Listing(m, entries, "")
catch e
  denied = occursin("permission", lowercase(sprint(showerror, e)))
  Listing(m, Entry[], denied ? "You don't have permission to see what's in this folder." :
                               "This folder couldn't be read.")
end

const _entries = Dict{String,Entry}()

"The Entry for any path, such as a sidebar place or a folder in the path bar"
entry(path) = get!(_entries, path) do
  st = stat(path)
  info = file_info(path, isdir(st))
  Entry(path, info.name, isdir(st) && !info.package, info.package, info.hidden,
        isdir(st) ? -1 : st.size, st.mtime, info.kind)
end

"A key that sorts \"File 2\" before \"File 10\", like Finder does"
natural(s) = [isdigit(c[1]) ? (0, length(lstrip(c, '0')), lstrip(c, '0')) : (1, 0, c)
              for c in (m.match for m in eachmatch(r"\d+|\D+", lowercase(s)))]

sort_key(by) =
  by == :name ? (e -> natural(e.name)) :
  by == :date ? (e -> (e.modified, natural(e.name))) :
  by == :size ? (e -> (e.size, natural(e.name))) :
                (e -> (lowercase(e.kind), natural(e.name)))

size_text(n) =
  n < 0 ? "--" :
  n < 1000 ? "$n bytes" :
  n < 1_000_000 ? "$(round(Int, n / 1e3)) KB" :
  n < 1_000_000_000 ? "$(round(n / 1e6, sigdigits=3)) MB" :
                      "$(round(n / 1e9, sigdigits=3)) GB"

day(t) = Libc.strftime("%Y-%m-%d", t)
date_text(t) = begin
  clock = lowercase(Libc.strftime("%-I:%M %p", t))
  day(t) == day(time()) ? "Today at $clock" :
  day(t) == day(time() - 86400) ? "Yesterday at $clock" :
  Libc.strftime("%-d %b %Y", t) * " at $clock"
end

const IMAGE_TYPES = Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp"])
is_image(e::Entry) = !e.folder && lowercase(splitext(e.path)[2]) in IMAGE_TYPES && 0 < e.size < 40_000_000

# --- the Finder ----------------------------------------------------------------

@def mutable struct Finder <: SemanticUI
  path::String = homedir()             # the folder the window shows
  back::Vector{String} = String[]
  forward::Vector{String} = String[]
  mode::Symbol = :list                 # :icons, :list, :columns or :sunburst
  selected::Set{String} = Set{String}()
  anchor::String = ""                  # where a shift-click selection starts
  cursor::String = ""                  # the item the arrow keys move from
  trail::Vector{String} = String[]     # the selected item in each column
  expanded::Set{String} = Set{String}()
  sort::Symbol = :name
  ascending::Bool = true
  show_hidden::Bool = false
  quicklook::Bool = false
  appearance::Symbol = :system         # :system follows the Mac. :light and :dark don't.
  dark::Union{Nothing,Bool} = nothing  # what the window was last set to
  us::Bool = false                     # Finder says "Favorites" and "Trash" in the US
  last_click::Tuple{String,Float64} = ("", 0.0)
  # A mouse press that may become a drag: what was pressed, and where
  press::Any = nothing
  dragging::Vector{String} = String[]  # the files being dragged
  drop::String = ""                    # the folder they'd land in if let go now
  marquee::Any = nothing               # the corners of the box being dragged out
  undo::Any = nothing                  # the (from, to) pairs of the last move
  menu::Any = nothing                  # the ContextMenu a right-click opened, while it's open
  usage::Any = nothing                 # the DiskUsage chart the sunburst view shows
  charted::String = ""                 # the folder the chart and the window last agreed on
  notice::Tuple{String,Float64} = ("", 0.0)
  typed::Tuple{String,Float64} = ("", 0.0)
  # Visible items in keyboard order, and how many fit in an icon view row
  order::Vector{Entry} = Entry[]
  per_row::Int = 1
  # Scroll positions live on Scroll nodes, so each one is kept between frames
  scroll::Scroll = Scroll(width(grow=grow), height(grow=grow), name="Files")
  columns::Dict{String,Scroll} = Dict{String,Scroll}()
  text_scroll::Scroll = Scroll(width(grow=grow), height(grow=grow), name="QuickLookText")
  # Nodes for files and folders, kept so double-clicks and hover can find them
  items::Dict{Any,Any} = Dict{Any,Any}()
  name_w::px = 300px                   # room for a name in the list view
  sorted::Dict{String,Tuple{Any,Vector{Entry}}} = Dict{String,Tuple{Any,Vector{Entry}}}()
  icon_budget::Float64 = 0.0
  icons_pending::Bool = false
  space::Tuple{Float64,Int} = (0.0, 0)
  # The parts with their own behaviour, made once by `build_finder`
  places::Vector{Any} = []
  buttons::Dict{Symbol,Any} = Dict{Symbol,Any}()
  search::Any = nothing
  quicklook_panel::Any = nothing
  quicklook_backdrop::Any = nothing
  toolbar::Any = nothing
  traffic_lights::Any = nothing
  # The size to lay out at when the Finder isn't in a window, e.g. for a PNG
  size::Tuple{px,px} = (1100px, 680px)
end

"A place in the sidebar"
@def mutable struct Place <: SemanticUI
  path::String = ""
  name::String = ""
  icon::String = ""
end

"A toolbar button. `action` says what it does."
@def mutable struct ToolButton <: SemanticUI
  action::Symbol = :back
  icon::String = ""
end

"""
The empty parts of the toolbar, and the top of the sidebar where the close,
minimise and zoom buttons sit. The window has no title bar, so you move it by
dragging these.
"""
@def mutable struct DragArea <: SemanticUI
  part::Symbol = :toolbar
end

@def mutable struct SearchField <: SemanticUI end
@def mutable struct ClearSearch <: SemanticUI end

"A file or folder. `style` says which view it's drawn in."
@def mutable struct FileItem <: SemanticUI
  entry::Any = nothing
  style::Symbol = :row
  depth::Int = 0
  index::Int = 0
  column::Int = 0
end

"The triangle that opens a folder in the list view"
@def mutable struct Disclosure <: SemanticUI
  path::String = ""
end

"A column heading in the list view. Clicking it sorts by that column."
@def mutable struct Heading <: SemanticUI
  key::Symbol = :name
  title::String = ""
end

"The empty space around the files, which clears the selection when clicked"
@def mutable struct Pane <: SemanticUI end

"One column in the column view"
@def mutable struct ColumnPane <: SemanticUI
  dir::String = ""
  index::Int = 1
end

"A folder in the path bar"
@def mutable struct Crumb <: SemanticUI
  path::String = ""
end

@def mutable struct QuickLookBackdrop <: SemanticUI end
@def mutable struct QuickLookPanel <: SemanticUI end

"""
The menu a right-click on a file opens. Its children are its MenuChoices, and
`lines` says which of them have a line under them.
"""
@def mutable struct ContextMenu <: SemanticUI
  at::Tuple{px,px} = (0px, 0px)        # where the click was
  opened::Float64 = 0.0
  lines::Vector{Int} = Int[]
end

"A choice in the ContextMenu. `action` does it."
@def mutable struct MenuChoice <: SemanticUI
  title::String = ""
  action::Any = nothing
end

"The rest of the window while the ContextMenu is open. A click on it closes the menu."
@def mutable struct MenuBackdrop <: SemanticUI end

finder(node) = begin
  while !(node isa Finder)
    node = node.parent
  end
  node
end

"A node that belongs to `f` and is kept for as long as `f` is"
own!(f, node) = (node.parent === nothing && setfield!(node, :parent, f); node)
item!(f, key, make) = get!(() -> own!(f, make()), f.items, key)


build_finder(path=homedir()) = begin
  home = homedir()
  f = Finder(path=abspath(expanduser(path)), us=endswith(locale(), "_US"))
  for (dir, icon) in (("/Applications", "grid"), (joinpath(home, "Desktop"), "display"),
                      (joinpath(home, "Documents"), "file-earmark"), (joinpath(home, "Downloads"), "arrow-down-circle"),
                      (home, "house"))
    isdir(dir) && push!(f.places, Place(path=dir, icon=icon))
  end
  push!(f.places, :locations)
  icloud = joinpath(home, "Library", "Mobile Documents", "com~apple~CloudDocs")
  isdir(icloud) && push!(f.places, Place(path=icloud, name="iCloud Drive", icon="cloud"))
  push!(f.places, Place(path="/", icon="hdd"))
  for v in (isdir("/Volumes") ? readdir("/Volumes", join=true) : String[])
    !islink(v) && sidebar_volume(v) && push!(f.places, Place(path=v, icon="hdd"))
  end
  bin = joinpath(home, ".Trash")
  isdir(bin) && push!(f.places, Place(path=bin, name=f.us ? "Trash" : "Bin", icon="trash3"))
  for p in f.places
    p isa Place && add_child!(f, p)
  end
  for (action, icon) in ((:back, "chevron-left"), (:forward, "chevron-right"), (:icons, "grid"),
                         (:list, "list-ul"), (:columns, "layout-three-columns"), (:sunburst, "bullseye"))
    f.buttons[action] = ToolButton(action=action, icon=icon)
    add_child!(f, f.buttons[action])
  end
  input = TextInput(placeholder="Search", font_family=FONT, font_size=13px,
                    look=(_, text) -> Row(width(grow=grow), height(grow=grow), clip=true, text))
  f.search = SearchField(input, ClearSearch())
  add_child!(f, f.search)
  f.toolbar = own!(f, DragArea(part=:toolbar))
  f.traffic_lights = own!(f, DragArea(part=:sidebar))
  f.quicklook_backdrop = own!(f, QuickLookBackdrop())
  f.quicklook_panel = own!(f, QuickLookPanel())
  f
end

query(f) = f.search.children[1].text
search_input(f) = f.search.children[1]::TextInput

"The size the Finder is laid out at"
window_size(f) = something(viewport(f), f.size)

"The folder whose name is in the toolbar: in the column view, the deepest one shown"
target(f) = begin
  f.mode == :columns || return f.path
  for p in Iterators.reverse(f.trail)
    isdir(p) && entry(p).folder && return p
  end
  f.path
end

"The files in `dir`, with hidden files and the search applied, in sort order"
entries(f, dir, q="") = begin
  l = listing(dir)
  key = (objectid(l), f.sort, f.ascending, f.show_hidden, q)
  cached = get(f.sorted, dir, nothing)
  cached !== nothing && cached[1] == key && return cached[2]
  q = lowercase(q)
  es = filter(e -> (f.show_hidden || !e.hidden) && (isempty(q) || occursin(q, lowercase(e.name))), l.entries)
  es = sort(es, by=sort_key(f.sort), rev=!f.ascending)
  f.sorted[dir] = (key, es)
  es
end

"Every row of the list view, with how deep in the tree it is"
list_rows(f) = begin
  out = Tuple{Entry,Int}[]
  add(dir, depth) = for e in entries(f, dir, depth == 0 ? query(f) : "")
    push!(out, (e, depth))
    e.folder && e.path in f.expanded && add(e.path, depth + 1)
  end
  add(f.path, 0)
  out
end

"The folders shown in the column view, from left to right"
column_dirs(f) = begin
  dirs = [f.path]
  for p in f.trail
    entry(p).folder || break
    push!(dirs, p)
  end
  dirs
end

# --- icons -------------------------------------------------------------------

"""
The system's icon for `e`, or a drawn one. A new icon takes a few milliseconds
to fetch, so each frame fetches only what fits in its budget. The rest arrive
over the next few frames.
"""
file_image(f, e::Entry, size) = begin
  px_ = size > 32px ? 256 : 64
  fetch = f.icon_budget > 0
  t = time()
  key = file_icon(e.path, e.folder || e.package, e.package, px=px_, fetch=fetch)
  f.icon_budget -= time() - t
  if key !== nothing
    Image(key, fixed(size), height(size))
  else
    fetch || (f.icons_pending = true)
    glyph = e.folder ? "folder-fill" : e.package ? "app" : "file-earmark"
    Box(fixed(size), height(size), Alignment.Center,
        Icon(glyph, size=size * 0.85, color=e.folder ? colours.folder : colours.dim))
  end
end

# --- sidebar -----------------------------------------------------------------

place_name(p::Place) = isempty(p.name) ? entry(p.path).name : p.name

describe(p::Place) = begin
  f = finder(p)
  on = target(f) == p.path
  Row(width(grow=grow), height(32px), padding(10px, 0px), radius(8px), child_gap=8px,
      background(f.drop == p.path ? colours.drop : on ? colours.sidebar_on : colours.sidebar), name="Place",
    Box(width(18px), Alignment.Center, Icon(p.icon, size=16px, color=colours.accent)),
    label(fit(place_name(p), SIDEBAR_W - 60px), weight=on ? "Semibold" : ""))
end

section(title) = Box(width(grow=grow), height(30px), padding(0px, 10px, 4px, 10px), Alignment.End,
  Row(width(grow=grow), label(title, 11px, color=colours.section, weight="Semibold")))

sidebar(f) = begin
  parts = Any[f.traffic_lights, section(f.us ? "Favorites" : "Favourites")]
  for p in f.places
    push!(parts, p === :locations ? section("Locations") : p)
  end
  Column(fixed(SIDEBAR_W), height(grow=grow), padding(0px, 10px, 10px, 10px), background(colours.sidebar),
         Alignment.Start, clip=true, name="Sidebar", parts...)
end

onkey(p::Place, ::KeyPress{Keys.mouse_left}) = (f = finder(p); focus(f); navigate!(f, p.path))

# --- toolbar -----------------------------------------------------------------

enabled(f, action) =
  action == :back ? !isempty(f.back) :
  action == :forward ? !isempty(f.forward) : true

describe(b::ToolButton) = begin
  f = finder(b)
  on = b.action == f.mode
  usable = enabled(f, b.action)
  fill = on ? colours.capsule_on : usable && ishovered(b) ? colours.hover : colours.capsule
  Box(width(b.action in (:back, :forward) ? 30px : 36px), height(28px), radius(14px), background(fill),
      Alignment.Center, name="Button",
    Icon(b.icon, size=b.action in (:back, :forward) ? 14px : 16px, color=usable ? colours.ink : colours.faint))
end

onkey(b::ToolButton, ::KeyPress{Keys.mouse_left}) = begin
  f = finder(b)
  focus(f)
  enabled(f, b.action) || return
  b.action == :back ? go_back!(f) :
  b.action == :forward ? go_forward!(f) :
  set_mode!(f, b.action)
end

divider() = Box(width(1px), height(16px), background(colours.line))

capsule(children...; name="") =
  Row(height(36px), padding(3px, 0px), radius(18px), child_gap=1px, background(colours.capsule),
      border(1px, :solid, colours.line), name=name, children...)

describe(s::SearchField) = begin
  f = finder(s)
  input, clear = s.children
  w = window_of(s)
  active = w !== nothing && w.focus === input
  Row(fixed(220px), height(36px), padding(12px, 0px), radius(18px), child_gap=6px, background(colours.capsule),
      border(1px, :solid, active ? colours.accent : colours.line), name="Search",
    Icon("search", size=13px, color=colours.dim),
    input,
    (isempty(input.text) ? () : (clear,))...)
end

onkey(s::SearchField, ::KeyPress{Keys.mouse_left}) = focus(s.children[1])
cursor(::SearchField) = :ibeam

describe(::ClearSearch) = Box(width(16px), height(16px), Alignment.Center, Icon("x-circle-fill", size=13px, color=colours.faint))
onkey(c::ClearSearch, ::KeyPress{Keys.mouse_left}) = clear_search!(finder(c))
cursor(::ClearSearch) = :arrow

describe(d::DragArea) = d.part == :toolbar ? toolbar(finder(d)) : Box(width(grow=grow), height(TOOLBAR_H - 12px))

onkey(d::DragArea, ::KeyPress{Keys.mouse_left}) = (f = finder(d); focus(f); drag_window!(window_of(d)))

toolbar(f) = Row(width(grow=grow), height(TOOLBAR_H), padding(12px, 0px), child_gap=12px, name="Toolbar",
  capsule(f.buttons[:back], divider(), f.buttons[:forward], name="History"),
  label(fit(entry(target(f)).name, 400px, size=15px), 15px, weight="Bold"),
  Box(width(grow=grow)),
  capsule(f.buttons[:icons], divider(), f.buttons[:list], f.buttons[:columns], f.buttons[:sunburst], name="Views"),
  f.search)

# --- path bar ----------------------------------------------------------------

describe(c::Crumb) = begin
  e = entry(c.path)
  Row(child_gap=4px, padding(3px, 2px), radius(4px), name="Crumb",
      background(finder(c).drop == c.path ? colours.drop : RGBA(0, 0, 0, 0)),
    file_image(finder(c), e, 14px),
    label(fit(e.name, 160px, size=11px), 11px, color=colours.dim))
end

onkey(c::Crumb, ::KeyPress{Keys.mouse_left}) = (f = finder(c); focus(f); navigate!(f, c.path))

ancestors(path) = begin
  out = [path]
  while path != "/"
    path = dirname(path)
    pushfirst!(out, path)
  end
  out
end

status(f) = begin
  message, at = f.notice
  time() - at < 6 && return message
  t, n = f.space
  if time() - t > 10
    n = try available_space(target(f)) catch; 0 end
    f.space = (time(), n)
  end
  total = length(f.order)
  chosen = count(e -> e.path in f.selected, f.order)
  items = chosen > 0 ? "$chosen of $total selected" : total == 1 ? "1 item" : "$total items"
  "$items, $(size_text(n)) available"
end

pathbar(f) = begin
  paths = ancestors(target(f))
  crumbs = Any[]
  for p in paths
    isempty(crumbs) || push!(crumbs, Icon("chevron-right", size=7px, color=colours.faint))
    push!(crumbs, item!(f, ("crumb", p), () -> Crumb(path=p)))
  end
  note = status(f)
  # Finder keeps the end of a long path in view, so the folders line up on the
  # right when they don't all fit. Each one is its name plus 24px of icon and
  # padding, and each arrow between them takes 17px with its gaps.
  need = sum(p -> text_width(fit(entry(p).name, 160px, size=11px), 11px) + 24px, paths) + 17px * (length(paths) - 1)
  room = window_size(f)[1] - SIDEBAR_W - 29px - text_width(note, 11px)
  Row(width(grow=grow), height(PATHBAR_H), padding(12px, 0px), child_gap=5px, border(1px, :solid, colours.line)[:top],
      name="PathBar",
    Row(width(grow=grow), height(grow=grow), clip=true, child_gap=5px,
        justify=need > room ? Alignment.End : Alignment.Start, crumbs...),
    Box(label(note, 11px, color=colours.dim)))
end

# --- file items -----------------------------------------------------------------

file_item(f, e::Entry; style, depth=0, index=0, column=0) = begin
  item = item!(f, e.path, () -> FileItem())
  item.entry = e
  item.style = style
  item.depth = depth
  item.index = index
  item.column = column
  item
end

describe(item::FileItem) =
  item.style == :row ? list_row(item) :
  item.style == :cell ? icon_cell(item) :
                        column_row(item)

cell(w, text, color; align=Alignment.Start) =
  Row(fixed(w), height(grow=grow), padding(8px, 0px), clip=true, justify=align, label(text, 12px, color=color))

list_row(item) = begin
  f, e = finder(item), item.entry
  on = e.path in f.selected
  ink, dim = on ? (colours.onsel, colours.onsel) : (colours.ink, colours.dim)
  fill = f.drop == e.path ? colours.drop : on ? colours.selected : iseven(item.index) ? colours.stripe : colours.bg
  arrow = e.folder ? item!(f, ("open", e.path), () -> Disclosure(path=e.path)) : Box(width(14px))
  Row(width(grow=grow), height(ROW), padding(8px, 0px), name="FileRow",
    Row(width(grow=grow), height(grow=grow), radius(6px), padding(0px, 6px, 0px, 6px), background(fill),
      Row(width(grow=grow), height(grow=grow), clip=true, child_gap=4px,
        (item.depth > 0 ? (Box(width(INDENT * item.depth)),) : ())...,
        arrow,
        file_image(f, e, 16px),
        Box(width(2px)),
        label(fit(e.name, f.name_w - INDENT * item.depth), color=ink)),
      cell(DATE_W, date_text(e.modified), dim),
      cell(SIZE_W, e.folder ? "--" : size_text(e.size), dim, align=Alignment.End),
      cell(KIND_W, e.kind, dim)))
end

describe(d::Disclosure) = begin
  f = finder(d)
  open = d.path in f.expanded
  Box(width(14px), height(grow=grow), Alignment.Center, name="Disclosure",
    Icon(open ? "chevron-down" : "chevron-right", size=9px, color=d.path in f.selected ? colours.onsel : colours.dim))
end

onkey(d::Disclosure, ::KeyPress{Keys.mouse_left}) = begin
  f = finder(d)
  focus(f)
  d.path in f.expanded ? delete!(f.expanded, d.path) : push!(f.expanded, d.path)
end

icon_cell(item) = begin
  f, e = finder(item), item.entry
  on = e.path in f.selected
  Column(fixed(CELL_W), height(CELL_H), padding(6px, 4px), child_gap=4px, Alignment.Center, name="FileCell",
    Box(width(ICON + 14px), height(ICON + 10px), radius(8px), Alignment.Center,
        background(f.drop == e.path ? colours.drop : on ? colours.icon_bg : colours.bg),
      file_image(f, e, ICON)),
    Box(radius(4px), padding(3px, 5px, 5px, 5px), background(on ? colours.selected : colours.bg),
      Text(cell_name(e.name), size=12px, family=FONT, color=on ? colours.onsel : colours.ink, wrap=WrapMode.newlines,
           align=TextAlign.Center, lineheight=1.25em)))
end

column_row(item) = begin
  f, e = finder(item), item.entry
  i = item.column
  on = i <= length(f.trail) && f.trail[i] == e.path
  focused = on && i == length(f.trail)
  fill = f.drop == e.path ? colours.drop : focused ? colours.selected : on ? colours.selected_2 : colours.bg
  ink = focused ? colours.onsel : colours.ink
  Row(width(grow=grow), height(COL_ROW), padding(6px, 0px), name="ColumnRow",
    Row(width(grow=grow), height(grow=grow), radius(5px), padding(6px, 0px), child_gap=6px, background(fill),
      file_image(f, e, 16px),
      Row(width(grow=grow), height(grow=grow), clip=true, label(fit(e.name, COL_W - 64px), color=ink)),
      e.folder ? Icon("chevron-right", size=9px, color=focused ? colours.onsel : colours.dim) : Box(width(9px))))
end

"Seconds between two clicks on the same item that make a double-click"
const DOUBLE_CLICK = 0.4

onkey(item::FileItem, ::KeyPress{Keys.mouse_left}) = begin
  Keys.ctrl in window_keys(item) && return menu_click!(item)
  f, e = finder(item), item.entry
  focus(f)
  last, t = f.last_click
  f.last_click = (e.path, time())
  last == e.path && time() - t < DOUBLE_CLICK && return open!(f, e)
  keys = window_keys(item)
  collapse = false
  if item.style == :column
    resize!(f.trail, item.column - 1)
    push!(f.trail, e.path)
    f.selected = Set([e.path])
  elseif Keys.cmd in keys
    e.path in f.selected ? delete!(f.selected, e.path) : push!(f.selected, e.path)
    f.anchor = f.cursor = e.path
  elseif Keys.shft in keys && !isempty(f.anchor)
    select_range!(f, e.path)
  elseif e.path in f.selected
    # Keep the rest of the selection until the button goes up, since this
    # press might start a drag of all of it
    collapse = true
    f.anchor = f.cursor = e.path
  else
    f.selected = Set([e.path])
    f.anchor = f.cursor = e.path
  end
  f.press = (kind=:item, path=e.path, at=mouse(item), collapse=collapse)
end

window_keys(node) = (w = window_of(node); w === nothing ? Keys(0) : w.keys)
mouse(node) = (w = window_of(node); w === nothing ? (0px, 0px) : (w.mouse[1], w.mouse[2]))

# --- the three views -------------------------------------------------------------

"Which items of a list with rows `step` tall fit in a Scroll, plus one either side"
visible_range(scroll::Scroll, n, step, top, fallback) = begin
  height = scroll.viewport > 0px ? scroll.viewport : fallback
  a = max(1, floor(Int, (scroll.offset - top) / step) + 1)
  b = min(n, a + ceil(Int, height / step) + 1)
  a, b
end

spacer(h) = Box(width(grow=grow), height(h))

describe(p::Pane) = (f = finder(p); Box(width(grow=grow), height(grow=grow),
                                         background(f.drop == f.path ? colours.drop : RGBA(0, 0, 0, 0))))

onkey(p::Pane, ::KeyPress{Keys.mouse_left}) = begin
  f = finder(p)
  focus(f)
  keys = window_keys(p)
  # A press on empty space starts a selection box. ⌘ and ⇧ add to the selection.
  if !(Keys.cmd in keys || Keys.shft in keys)
    empty!(f.selected)
    f.anchor = f.cursor = ""
  end
  f.press = (kind=:marquee, at=mouse(p), base=copy(f.selected))
end

describe(h::Heading) = begin
  f = finder(h)
  on = f.sort == h.key
  arrow = on ? (Icon(f.ascending ? "chevron-up" : "chevron-down", size=8px, color=colours.dim),) : ()
  w = h.key == :date ? fixed(DATE_W) : h.key == :size ? fixed(SIZE_W) : h.key == :kind ? fixed(KIND_W) : width(grow=grow)
  Row(w, height(grow=grow), padding(8px, 0px), child_gap=5px, clip=true,
      justify=h.key == :size ? Alignment.End : Alignment.Start,
      border(1px, :solid, h.key == :name ? colours.bg : colours.line)[:left], name="Heading",
    label(h.title, 12px, color=on ? colours.ink : colours.dim, weight=on ? "Semibold" : ""), arrow...)
end

onkey(h::Heading, ::KeyPress{Keys.mouse_left}) = begin
  f = finder(h)
  focus(f)
  if f.sort == h.key
    f.ascending = !f.ascending
  else
    f.sort = h.key
    f.ascending = h.key in (:name, :kind)
  end
end

headings(f) = Row(width(grow=grow), height(HEADER_H), padding(8px, 0px), border(1px, :solid, colours.line)[:bottom], name="Headings",
  Row(width(grow=grow), height(grow=grow), padding(0px, 6px, 0px, 24px),
    (item!(f, ("heading", key), () -> Heading(key=key, title=title))
     for (key, title) in ((:name, "Name"), (:date, "Date Modified"), (:size, "Size"), (:kind, "Kind")))...))

message(text) = Box(width(grow=grow), height(grow=grow), Alignment.Center, label(text, 13px, color=colours.dim))

list_view(f, w, h) = begin
  rows = list_rows(f)
  f.order = first.(rows)
  # The name column gets what the other columns, the padding and the icon leave
  f.name_w = w - DATE_W - SIZE_W - KIND_W - 80px
  a, b = visible_range(f.scroll, length(rows), ROW, 0px, h)
  shown = Any[spacer(ROW * (a - 1))]
  for i in a:b
    e, depth = rows[i]
    push!(shown, file_item(f, e, style=:row, depth=depth, index=i))
  end
  push!(shown, spacer(ROW * (length(rows) - b)))
  Column(width(grow=grow), height(grow=grow), Alignment.Start, name="ListView",
    headings(f),
    Stack(width(grow=grow), height(grow=grow), Alignment.Start,
      item!(f, "pane", () -> Pane()),
      reuse!(f.scroll, Column(width(grow=grow), Alignment.Start, name="Rows", shown...))))
end

icon_view(f, w, h) = begin
  es = entries(f, f.path, query(f))
  f.order = es
  per = f.per_row = max(1, floor(Int, (w - 2GRID_PAD) / CELL_W))
  nrows = cld(length(es), per)
  a, b = visible_range(f.scroll, nrows, CELL_H, GRID_PAD, h)
  shown = Any[spacer(CELL_H * (a - 1))]
  for r in a:b
    cells = (file_item(f, es[i], style=:cell, index=i) for i in (r-1)*per+1:min(r*per, length(es)))
    push!(shown, Row(Alignment.Start, name="GridRow", cells...))
  end
  push!(shown, spacer(CELL_H * (nrows - b)))
  Stack(width(grow=grow), height(grow=grow), Alignment.Start, name="IconView",
    item!(f, "pane", () -> Pane()),
    reuse!(f.scroll, Column(width(grow=grow), padding(GRID_PAD), Alignment.Start, name="Grid", shown...)))
end

column_scroll(f, dir) = get!(f.columns, dir) do
  Scroll(width(grow=grow), height(grow=grow), name="Column")
end

describe(c::ColumnPane) = begin
  f = finder(c)
  es = entries(f, c.dir, c.index == 1 ? query(f) : "")
  c.index == max(1, length(f.trail)) && (f.order = es)
  scroll = column_scroll(f, c.dir)
  l = listing(c.dir)
  a, b = visible_range(scroll, length(es), COL_ROW, 4px, window_size(f)[2])
  rows = Any[spacer(COL_ROW * (a - 1))]
  for i in a:b
    push!(rows, file_item(f, es[i], style=:column, index=i, column=c.index))
  end
  push!(rows, spacer(COL_ROW * (length(es) - b)))
  Box(fixed(COL_W), height(grow=grow), border(1px, :solid, colours.line)[:right], Alignment.Start, name="ColumnPane",
      background(f.drop == c.dir ? colours.drop : RGBA(0, 0, 0, 0)),
    isempty(l.error) ? reuse!(scroll, Column(width(grow=grow), padding(0px, 4px), Alignment.Start, rows...)) :
                       Box(width(grow=grow), padding(16px), Text(l.error, size=12px, family=FONT, color=colours.dim)))
end

onkey(c::ColumnPane, ::KeyPress{Keys.mouse_left}) = begin
  f = finder(c)
  focus(f)
  resize!(f.trail, min(length(f.trail), c.index - 1))
  f.selected = isempty(f.trail) ? Set{String}() : Set([f.trail[end]])
end

"An image shrunk to fit inside `w` × `h`"
fitted_image(path, w, h; corner=0px) = begin
  aspect = image_aspect(path)
  iw, ih = aspect >= w / h ? (w, w / aspect) : (h * aspect, h)
  Image(path, width(iw), height(ih), radius(corner))
end

info_row(name, value) = Row(width(grow=grow), height(16px), child_gap=8px,
  Row(fixed(70px), height(grow=grow), justify=Alignment.End, label(name, 11px, color=colours.dim)),
  Row(width(grow=grow), height(grow=grow), clip=true, label(value, 11px)))

preview(f, e::Entry) =
  Column(fixed(PREVIEW_W), height(grow=grow), padding(16px, 24px), child_gap=10px, Alignment.Center, name="Preview",
    is_image(e) ? fitted_image(e.path, PREVIEW_W - 60px, 180px, corner=4px) : file_image(f, e, 128px),
    Text(e.name, size=13px, family=FONT, subfamily="Semibold", color=colours.ink, align=TextAlign.Center),
    label(e.kind * (e.size >= 0 ? " – " * size_text(e.size) : ""), 11px, color=colours.dim),
    spacer(8px),
    Column(width(grow=grow), child_gap=8px, Alignment.Start,
      label("Information", 13px, weight="Semibold"),
      info_row("Modified", date_text(e.modified)),
      info_row("Kind", e.kind),
      info_row("Where", fit(dirname(e.path), PREVIEW_W - 120px, size=11px))))

column_view(f, w, h) = begin
  dirs = column_dirs(f)
  panes = Any[item!(f, ("column", d), () -> ColumnPane(dir=d)) for d in dirs]
  for (i, p) in enumerate(panes)
    p.index = i
  end
  last = isempty(f.trail) ? nothing : entry(f.trail[end])
  last !== nothing && !last.folder && push!(panes, preview(f, last))
  total = COL_W * length(dirs) + (length(panes) > length(dirs) ? PREVIEW_W : 0px)
  Row(width(grow=grow), height(grow=grow), Alignment.Start, clip=true, name="ColumnView",
      justify=total > w ? Alignment.End : Alignment.Start, panes...)
end

content(f, w, h) = begin
  l = listing(f.path)
  isempty(l.error) || (f.order = Entry[]; return message(l.error))
  f.mode == :list ? list_view(f, w, h - HEADER_H) :
  f.mode == :icons ? icon_view(f, w, h) :
  f.mode == :sunburst ? sunburst_view(f, w, h) :
                        column_view(f, w, h)
end

# --- the sunburst view ------------------------------------------------------------

"The Disk Usage example's chart of the folder the window shows, laid out at `w` × `h`"
sunburst_view(f, w, h) = begin
  u = f.usage
  u.size = (w, h)
  u.appearance = f.dark ? :dark : :light
  # For the counts in the path bar
  f.order = entries(f, f.path)
  u
end

"""
Keep the chart and the window on the same folder. Going to a folder in the
window zooms the chart there, and clicking a slice or the middle of the chart
takes the window there. A folder outside the one the chart read starts a new
scan.
"""
sync_sunburst!(f) = begin
  isdir(f.path) || return
  u = f.usage
  if u === nothing
    u = f.usage = own!(f, DiskUsage(Scan(f.path), embedded=true, onmenu=item -> sunburst_menu!(f, item)))
  elseif f.path != f.charted
    item = find_item(u.scan.root, f.path)
    item === nothing ? scan!(u, f.path) : item === u.zoom || zoom!(u, item)
  else
    here = item_path(u.zoom)
    here == f.path || navigate!(f, here)
  end
  f.charted = f.path
end

"The chart's Item for the folder `dir`, when the scan from `root` has read that far"
find_item(root, dir) = begin
  top = item_path(root)
  dir == top && return root
  startswith(dir, rstrip(top, '/') * "/") || return nothing
  item = root
  for name in splitpath(relpath(dir, top))
    i = findfirst(c -> c.name == name, item.children)
    i === nothing && return nothing
    item = item.children[i]
  end
  item.folder ? item : nothing
end

"A right-click on a slice or a row of the chart opens Finder's menu for what it stands for"
sunburst_menu!(f, item) = begin
  p = item_path(item)
  f.selected = Set([p])
  f.anchor = f.cursor = p
  open_menu!(f, mouse(f))
end

"Read these folders again, if the chart has them, after files were added to them"
rechart!(f, dirs) = begin
  f.usage === nothing && return
  for d in dirs
    item = find_item(f.usage.scan.root, d)
    item === nothing || rescan_item!(f.usage, item)
  end
end

# --- Quick Look ----------------------------------------------------------------

"The item that Quick Look and the arrow keys start from"
current(f) =
  f.mode == :columns ? (isempty(f.trail) ? nothing : entry(f.trail[end])) :
  f.mode == :sunburst ? (ispath(f.cursor) ? entry(f.cursor) : nothing) :
  (i = findfirst(e -> e.path == f.cursor, f.order); i === nothing ? nothing : f.order[i])

"The start of a text file, or `nothing` when it doesn't look like text"
text_preview(path) = begin
  bytes = open(io -> read(io, 64_000), path)
  0x00 in bytes && return nothing
  s = String(bytes)
  isvalid(s) || return nothing
  join(first(split(s, '\n'), 400), '\n')
end

describe(::QuickLookBackdrop) = Box(width(grow=grow), height(grow=grow), background(colours.backdrop))
onkey(q::QuickLookBackdrop, ::KeyPress{Keys.mouse_left}) = (finder(q).quicklook = false)

describe(q::QuickLookPanel) = begin
  f = finder(q)
  e = current(f)
  w, h = window_size(f)
  pw, ph = min(760px, w - 120px), min(560px, h - 100px)
  text = e === nothing || e.folder || is_image(e) || e.size > 5_000_000 ? nothing : try text_preview(e.path) catch; nothing end
  body = e === nothing ? message("Nothing is selected.") :
    is_image(e) ? Box(width(grow=grow), height(grow=grow), padding(16px), Alignment.Center,
                      fitted_image(e.path, pw - 32px, ph - 76px)) :
    text !== nothing ? reuse!(f.text_scroll, Box(width(grow=grow), padding(14px), Alignment.Start, clip=true,
                                                 Text(text, size=12px, family="Menlo", color=colours.ink, wrap=WrapMode.newlines))) :
    Column(width(grow=grow), height(grow=grow), child_gap=12px, Alignment.Center, justify=Alignment.Center,
      file_image(f, e, 160px),
      label(e.name, 15px, weight="Semibold"),
      label(e.kind * (e.size >= 0 ? " – " * size_text(e.size) : ""), 12px, color=colours.dim),
      label("Modified " * date_text(e.modified), 12px, color=colours.dim))
  Column(width(pw), height(ph), radius(12px), background(colours.bg), border(1px, :solid, colours.panel_line),
         clip=true, Alignment.Start, name="QuickLook",
    Row(width(grow=grow), height(40px), padding(16px, 0px), child_gap=8px, background(colours.sidebar),
        border(1px, :solid, colours.line)[:bottom],
      label(e === nothing ? "Quick Look" : fit(e.name, pw - 220px), 13px, weight="Semibold"),
      Box(width(grow=grow)),
      Box(label("space or esc to close", 11px, color=colours.dim))),
    body)
end

# --- the whole window -------------------------------------------------------------

"Pick light or dark colours, and tell the window so its own parts match"
use_appearance!(f) = begin
  dark = f.appearance == :system ? dark_mode() : f.appearance == :dark
  use!(dark ? DARK : LIGHT)
  input = search_input(f)
  input.color = colours.ink
  input.placeholder_color = colours.dim
  win = window_of(f)
  win === nothing || dark === f.dark || set_dark!(win, dark)
  f.dark = dark
end

describe(f::Finder) = begin
  use_appearance!(f)
  f.mode == :sunburst && sync_sunburst!(f)
  w, h = window_size(f)
  # Fetching icons gets 12 ms of each frame
  f.icon_budget = 0.012
  f.icons_pending = false
  window = Row(width(grow=grow), height(grow=grow), Alignment.Start, name="Finder",
    sidebar(f),
    Column(width(grow=grow), height(grow=grow), Alignment.Start, background(colours.bg), name="Main",
      f.toolbar,
      content(f, w - SIDEBAR_W, h - TOOLBAR_H - PATHBAR_H),
      pathbar(f)))
  win = window_of(f)
  # Draw again soon while icons are still arriving or the search caret blinks
  charting = f.mode == :sunburst && f.usage !== nothing && busy(f.usage)
  win === nothing || (win.animating = f.icons_pending || win.focus === search_input(f) || charting)
  layers = Any[window]
  f.quicklook && push!(layers, f.quicklook_backdrop, f.quicklook_panel)
  isempty(f.dragging) || win === nothing || push!(layers, float_layer(drag_preview(f, win.mouse)))
  f.marquee === nothing || push!(layers, float_layer(marquee_box(f.marquee)))
  f.menu === nothing || push!(layers, item!(f, :menu_backdrop, MenuBackdrop), float_layer(f.menu))
  length(layers) == 1 ? window : Stack(width(grow=grow), height(grow=grow), name="Finder", layers...)
end

# --- the menu a right-click opens -----------------------------------------------

const MENU_W = 220px
const MENU_ROW = 22px

"""
A right-click or a control-click on a file. Like Finder, it selects the file
unless it's selected already, then opens the menu for what's selected.
"""
menu_click!(item::FileItem) = begin
  f, e = finder(item), item.entry
  focus(f)
  if item.style == :column
    resize!(f.trail, item.column - 1)
    push!(f.trail, e.path)
    f.selected = Set([e.path])
  elseif !(e.path in f.selected)
    f.selected = Set([e.path])
  end
  f.anchor = f.cursor = e.path
  open_menu!(f, mouse(item))
end

onkey(item::FileItem, ::KeyPress{Keys.mouse_right}) = menu_click!(item)

"Open the menu for the selected files at `at`, a point in the window"
open_menu!(f, at) = begin
  chosen = sort!(collect(f.selected))
  isempty(chosen) && return
  n = length(chosen)
  m = own!(f, ContextMenu(at=at, opened=time()))
  choices = Any["Open" => () -> open_selection!(f),
                :line,
                "Quick Look" => () -> (f.quicklook = true),
                "Duplicate" => () -> duplicate!(f, chosen),
                :line,
                (n == 1 ? "Copy Path" : "Copy $n Paths") => () -> copy_paths!(f, chosen)]
  Sys.isapple() && push!(choices, "Show in Finder" => () -> run(`open -R $chosen`, wait=false))
  for c in choices
    c === :line ? push!(m.lines, length(m.children)) : add_child!(m, MenuChoice(title=first(c), action=last(c)))
  end
  f.menu = m
end

describe(m::ContextMenu) = begin
  f = finder(m)
  parts = Any[]
  for (i, c) in enumerate(m.children)
    push!(parts, c)
    i in m.lines && push!(parts, Box(width(grow=grow), height(11px), padding(9px, 5px),
                                     Box(width(grow=grow), height(1px), background(colours.line))))
  end
  # It opens below and to the right of the pointer, unless that would go past
  # the edge of the window
  w, h = window_size(f)
  tall = 10px + MENU_ROW * length(m.children) + 11px * length(m.lines)
  x, y = m.at
  x + MENU_W > w - 4px && (x = max(4px, x - MENU_W))
  y + tall > h - 4px && (y = max(4px, h - 4px - tall))
  Column(fixed(MENU_W), padding(5px), radius(7px), Alignment.Start, background(colours.capsule),
         border(1px, :solid, colours.panel_line), offset_x=x, offset_y=y, name="ContextMenu", parts...)
end

describe(c::MenuChoice) = begin
  on = ishovered(c)
  Row(width(grow=grow), height(MENU_ROW), padding(9px, 0px), radius(4px), name="MenuChoice",
      background(on ? colours.selected : RGBA(0, 0, 0, 0)),
    label(c.title, color=on ? colours.onsel : colours.ink))
end

"Close the menu, then do what `c` says"
choose!(c::MenuChoice) = (finder(c).menu = nothing; c.action())

onkey(c::MenuChoice, ::KeyPress{Keys.mouse_left}) = choose!(c)
# You can also hold the right button down, move to a choice and let go. A quick
# click leaves the menu open, as Finder does.
onkey(c::MenuChoice, ::KeyRelease{Keys.mouse_right}) = time() - c.parent.opened > 0.3 && choose!(c)

describe(::MenuBackdrop) = Box(width(grow=grow), height(grow=grow))
onkey(b::MenuBackdrop, ::KeyPress) = (finder(b).menu = nothing)

"A name for a copy of `path` that isn't taken yet: “name copy.txt”, then “name copy 2.txt”"
copy_name(path) = begin
  dir, base = splitdir(path)
  stem, ext = entry(path).folder ? (base, "") : splitext(base)
  n = 1
  while true
    to = joinpath(dir, stem * (n == 1 ? " copy" : " copy $n") * ext)
    ispath(to) || islink(to) || return to
    n += 1
  end
end

"Copy each of `paths` next to itself, and select the copies"
duplicate!(f, paths) = begin
  made, failed = String[], String[]
  for p in paths
    to = copy_name(p)
    try
      cp(p, to)
      push!(made, to)
    catch
      push!(failed, basename(p))
    end
  end
  refresh!(unique(dirname.(paths))...)
  rechart!(f, unique(dirname.(paths)))
  if !isempty(made)
    f.selected = Set(made)
    f.anchor = f.cursor = last(made)
    f.mode == :columns && !isempty(f.trail) && (f.trail[end] = last(made))
  end
  f.notice = (isempty(failed) ? "Duplicated $(items_text(length(made)))." :
                                "“$(failed[1])” couldn't be duplicated.", time())
end

copy_paths!(f, paths) = begin
  clipboard(join(paths, "\n"))
  f.notice = (length(paths) == 1 ? "Copied the path of “$(entry(paths[1]).name)”." :
                                   "Copied the paths of $(items_text(length(paths))).", time())
end

# --- dragging ------------------------------------------------------------------
#
# A press on a file can become a drag that moves the selection to another
# folder. A press on empty space can become a box that selects what it touches.

"How far the mouse moves after a press before it counts as a drag"
const DRAG_START = 4px

onmouse(f::Finder, e::MouseMove) = begin
  p = f.press
  (p === nothing || !(Keys.mouse_left in e.window.keys)) && return
  pos = e.position
  if p.kind == :item
    if isempty(f.dragging)
      abs(pos[1] - p.at[1]) + abs(pos[2] - p.at[2]) < DRAG_START && return
      f.dragging = p.path in f.selected ? sort!(collect(f.selected)) : [p.path]
    end
    f.drop = drop_target(f, e.window, pos)
  elseif f.mode != :columns
    f.marquee = (p.at, pos)
    select_in_box!(f, p.at, pos, p.base)
  end
end

onkey(f::Finder, e::KeyRelease{Keys.mouse_left}) = begin
  p, files, dest = f.press, f.dragging, f.drop
  f.press, f.dragging, f.drop, f.marquee = nothing, String[], "", nothing
  p === nothing && return
  if !isempty(files)
    isempty(dest) || drop!(f, files, dest, copy=Keys.opt in e.window.keys)
  elseif p.kind == :item && p.collapse
    f.selected = Set([p.path])
  end
end

"The folder that dragged files would land in if let go at `pos`, or \"\" for nowhere"
drop_target(f, w, pos) = begin
  dest = drop_folder(f, hittest(w, pos))
  (isempty(dest) || !isdir(dest)) && return ""
  # A folder can't go inside itself, and files already there have nowhere to go
  any(p -> dest == p || startswith(dest, p * "/"), f.dragging) && return ""
  all(p -> dirname(p) == dest, f.dragging) && return ""
  dest
end

"Which folder the thing under the mouse stands for"
drop_folder(f, node) = begin
  while node !== nothing
    node isa FileItem && return node.entry.folder ? node.entry.path : dirname(node.entry.path)
    node isa Disclosure && return node.path
    node isa Place && return node.path
    node isa Crumb && return node.path
    node isa ColumnPane && return node.dir
    node isa Pane && return f.path
    node = node.parent
  end
  ""
end

"Forget what was read about these folders, so they're read again"
refresh!(dirs...) = (foreach(d -> delete!(_listings, d), dirs); empty!(_entries))

items_text(n) = n == 1 ? "1 item" : "$n items"

"""
Move `files` into the folder `dest`, the way Finder does. They're copied instead
when `copy` is set or when `dest` is on another disk. A file never replaces one
that's already there with the same name: it stays where it is.
"""
drop!(f, files, dest; copy=false) = begin
  moved, copied, kept, failed = Tuple{String,String}[], String[], String[], String[]
  for from in files
    dirname(from) == dest && continue
    to = joinpath(dest, basename(from))
    if ispath(to) || islink(to)
      push!(kept, basename(from))
      continue
    end
    copying = copy || stat(from).device != stat(dest).device
    try
      copying ? (cp(from, to); push!(copied, to)) : (mv(from, to); push!(moved, (from, to)))
    catch
      push!(failed, basename(from))
    end
  end
  refresh!(dest, unique(dirname.(files))...)
  f.selected = Set(vcat(last.(moved), copied))
  f.anchor = f.cursor = ""
  filter!(ispath, f.trail)
  isempty(moved) || (f.undo = moved)
  name = entry(dest).name
  f.notice = (!isempty(failed) ? "“$(failed[1])” couldn't be moved to “$(name)”." :
              length(kept) == 1 ? "“$(kept[1])” is already in “$(name)”, so it stayed where it was." :
              length(kept) > 1 ? "$(length(kept)) items are already in “$(name)”, so they stayed where they were." :
              !isempty(copied) ? "Copied $(items_text(length(copied))) to “$(name)”." :
                                 "Moved $(items_text(length(moved))) to “$(name)”. Press ⌘Z to undo.", time())
end

"Put the files from the last move back where they were"
undo!(f) = begin
  moves, f.undo = f.undo, nothing
  moves === nothing && return (f.notice = ("There's no move to undo.", time()))
  back = 0
  for (from, to) in reverse(moves)
    ispath(to) && !ispath(from) || continue
    try
      mv(to, from)
      back += 1
    catch
    end
  end
  refresh!(unique(dirname.(first.(moves)))..., unique(dirname.(last.(moves)))...)
  f.selected = Set(first.(moves))
  f.notice = ("Moved $(items_text(back)) back.", time())
end

"Select what the box from `a` to `b` touches, along with what was selected in `base`"
select_in_box!(f, a, b, base) = begin
  x0, x1 = minmax(a[1], b[1])
  y0, y1 = minmax(a[2], b[2])
  touched(x, y, w, h) = x <= x1 && x + w >= x0 && y <= y1 && y + h >= y0
  hits = String[]
  for (i, e) in enumerate(f.order)
    hit = if f.mode == :list
      touched(SIDEBAR_W + 8px, TOOLBAR_H + HEADER_H - f.scroll.offset + ROW * (i - 1), px(Inf), ROW)
    else
      r, c = divrem(i - 1, f.per_row)
      touched(SIDEBAR_W + GRID_PAD + CELL_W * c + 14px, TOOLBAR_H + GRID_PAD - f.scroll.offset + CELL_H * r + 6px,
              CELL_W - 28px, CELL_H - 12px)
    end
    hit && push!(hits, e.path)
  end
  f.selected = union(base, hits)
  isempty(hits) || (f.anchor = f.cursor = last(hits))
end

"What follows the mouse while files are dragged: the first one's icon and name, and how many there are"
drag_preview(f, (x, y)) = begin
  e = entry(f.dragging[1])
  n = length(f.dragging)
  Row(padding(6px, 4px), radius(6px), child_gap=6px, background(colours.capsule), border(1px, :solid, colours.line),
      offset_x=x + 12px, offset_y=y + 8px, name="DragPreview",
    file_image(f, e, 24px),
    label(fit(e.name, 220px)),
    (n > 1 ? (Box(radius(9px), padding(6px, 3px), background(colorant"rgb(230,65,55)"),
                  label(string(n), 11px, color=colorant"white", weight="Bold")),) : ())...)
end

"The box being dragged out to select files"
marquee_box(((ax, ay), (bx, by))) =
  Box(width(abs(bx - ax)), height(abs(by - ay)), background(colours.marquee), border(1px, :solid, colours.accent),
      offset_x=min(ax, bx), offset_y=min(ay, by), name="SelectionBox")

"A layer over the whole window, for something drawn at a point like the mouse"
float_layer(child) = Box(width(grow=grow), height(grow=grow), Alignment.Start, child)

# --- actions -----------------------------------------------------------------

navigate!(f, dir; record=true) = begin
  isdir(dir) || return
  record && dir != f.path && (push!(f.back, f.path); empty!(f.forward))
  f.path = dir
  empty!(f.selected)
  empty!(f.trail)
  f.anchor = f.cursor = ""
  f.scroll.offset = 0px
  f.quicklook = false
  f.menu = nothing
  clear_search!(f)
end

go_back!(f) = isempty(f.back) || (push!(f.forward, f.path); navigate!(f, pop!(f.back), record=false))
go_forward!(f) = isempty(f.forward) || (push!(f.back, f.path); navigate!(f, pop!(f.forward), record=false))

"Go to the enclosing folder and select the folder you came from"
enclosing!(f) = begin
  from = target(f)
  from == "/" && return
  navigate!(f, dirname(from))
  select_only!(f, from)
end

select_only!(f, path) = begin
  f.selected = Set([path])
  f.anchor = f.cursor = path
  f.mode == :columns && (f.trail = [path])
  reveal!(f, path)
end

open!(f, e::Entry) = e.folder ? navigate!(f, e.path) : open_url(e.path)

open_selection!(f) = begin
  chosen = f.mode == :columns ? (isempty(f.trail) ? Entry[] : [entry(f.trail[end])]) :
           f.mode == :sunburst ? [entry(p) for p in sort!(collect(f.selected)) if ispath(p)] :
                                 filter(e -> e.path in f.selected, f.order)
  folders = filter(e -> e.folder, chosen)
  length(folders) == 1 && return navigate!(f, folders[1].path)
  foreach(e -> e.folder || open_url(e.path), first(chosen, 10))
end

set_mode!(f, mode) = begin
  mode == f.mode && return
  # A scan that's stopped part way can't go on, so the next sunburst starts a new one
  if f.mode == :sunburst && f.usage !== nothing && running(f.usage.scan)
    stop!(f.usage.scan)
    f.usage = nothing
  end
  if f.mode == :columns
    dir = target(f)
    chosen = isempty(f.trail) ? "" : f.trail[end]
    f.path = dir
    f.selected = chosen == "" || chosen == dir ? Set{String}() : Set([chosen])
    f.anchor = f.cursor = chosen == dir ? "" : chosen
  elseif mode == :columns
    f.trail = isempty(f.cursor) || dirname(f.cursor) != f.path ? String[] : [f.cursor]
  end
  f.mode = mode
  f.scroll.offset = 0px
  isempty(f.cursor) || reveal!(f, f.cursor)
end

clear_search!(f) = begin
  input = search_input(f)
  input.text = ""
  input.cursor = input.anchor = 0
end

select_range!(f, to) = begin
  paths = [e.path for e in f.order]
  a, b = findfirst(==(f.anchor), paths), findfirst(==(to), paths)
  (a === nothing || b === nothing) && return
  f.selected = Set(paths[min(a, b):max(a, b)])
  f.cursor = to
end

"Scroll so `path` is in view"
reveal!(f, path) = begin
  i = findfirst(e -> e.path == path, f.order)
  i === nothing && return
  if f.mode == :list
    scroll_into_view!(f.scroll, ROW * (i - 1), ROW * i)
  elseif f.mode == :icons
    r = cld(i, f.per_row)
    scroll_into_view!(f.scroll, GRID_PAD + CELL_H * (r - 1), GRID_PAD + CELL_H * r)
  else
    dir = dirname(path)
    haskey(f.columns, dir) && scroll_into_view!(f.columns[dir], 4px + COL_ROW * (i - 1), 4px + COL_ROW * i)
  end
end

"Move the selection with an arrow key"
move!(f, key, extend) = begin
  f.mode == :columns && return move_column!(f, key)
  f.mode == :sunburst && return
  n = length(f.order)
  n == 0 && return
  i = findfirst(e -> e.path == f.cursor, f.order)
  if f.mode == :list && i !== nothing && key in (Keys.left, Keys.right)
    e = f.order[i]
    if key == Keys.right
      e.folder && push!(f.expanded, e.path)
    elseif e.path in f.expanded
      delete!(f.expanded, e.path)
    elseif dirname(e.path) != f.path
      select_only!(f, dirname(e.path))
    end
    return
  end
  step = key == Keys.up ? -1 : key == Keys.down ? 1 : key == Keys.left ? -1 : 1
  f.mode == :icons && key in (Keys.up, Keys.down) && (step *= f.per_row)
  j = i === nothing ? (step > 0 ? 1 : n) : clamp(i + step, 1, n)
  if extend && !isempty(f.anchor)
    select_range!(f, f.order[j].path)
    reveal!(f, f.order[j].path)
  else
    select_only!(f, f.order[j].path)
  end
end

move_column!(f, key) = begin
  col = max(1, length(f.trail))
  if key == Keys.right
    isempty(f.trail) && return move_column!(f, Keys.down)
    e = entry(f.trail[end])
    e.folder || return
    es = entries(f, e.path)
    isempty(es) || (push!(f.trail, es[1].path); f.selected = Set([es[1].path]); reveal!(f, es[1].path))
  elseif key == Keys.left
    length(f.trail) > 1 && (pop!(f.trail); f.selected = Set([f.trail[end]]))
  else
    dir = column_dirs(f)[col]
    es = entries(f, dir, col == 1 ? query(f) : "")
    isempty(es) && return
    i = isempty(f.trail) ? nothing : findfirst(e -> e.path == f.trail[end], es)
    j = i === nothing ? 1 : clamp(i + (key == Keys.up ? -1 : 1), 1, length(es))
    resize!(f.trail, col - 1)
    push!(f.trail, es[j].path)
    f.selected = Set([es[j].path])
    reveal!(f, es[j].path)
  end
end

const LETTERS = Dict{Keys,Char}()
for c in 'a':'z'; LETTERS[getproperty(Keys, Symbol(c))] = c end
for d in 0:9; LETTERS[getproperty(Keys, Symbol(d))] = Char('0' + d) end
LETTERS[Keys.space] = ' '
LETTERS[Keys.period] = '.'
LETTERS[Keys.minus] = '-'

"Select the first item whose name starts with what's been typed in the last second"
type_select!(f, c) = begin
  f.mode == :sunburst && return
  typed, t = f.typed
  typed = time() - t < 1 ? typed * c : string(c)
  f.typed = (typed, time())
  i = findfirst(e -> startswith(lowercase(e.name), typed), f.order)
  i === nothing && return
  if f.mode == :columns
    col = max(1, length(f.trail))
    resize!(f.trail, col - 1)
    push!(f.trail, f.order[i].path)
    f.selected = Set([f.order[i].path])
    reveal!(f, f.order[i].path)
  else
    select_only!(f, f.order[i].path)
  end
end

const VIEW_KEYS = Dict(getproperty(Keys, Symbol(1)) => :icons, getproperty(Keys, Symbol(2)) => :list,
                       getproperty(Keys, Symbol(3)) => :columns, getproperty(Keys, Symbol(4)) => :sunburst)

is_mouse(k) = k in (Keys.mouse_left, Keys.mouse_right, Keys.mouse_middle)

onkey(f::Finder, e::KeyPress{K}) where K = begin
  is_mouse(K) && return
  # While the menu is open, esc closes it and other keys do nothing
  f.menu === nothing || return K == Keys.escape && (f.menu = nothing)
  w = e.window
  cmd, shift, opt = Keys.cmd in w.keys, Keys.shft in w.keys, Keys.opt in w.keys
  typing = w.focus === search_input(f)
  if K == Keys.escape
    if !isempty(f.dragging)
      f.press, f.dragging, f.drop = nothing, String[], ""
    else
      f.quicklook ? (f.quicklook = false) : (clear_search!(f); focus(f))
    end
  elseif cmd && opt && K == Keys.i
    toggle_inspector!(w)
  elseif cmd && shift && K == Keys.period
    f.show_hidden = !f.show_hidden
  elseif cmd && K == Keys.f
    focus(search_input(f))
  elseif cmd && haskey(VIEW_KEYS, K)
    set_mode!(f, VIEW_KEYS[K])
  elseif cmd && K == Keys.r && f.mode == :sunburst && f.usage !== nothing
    rescan_item!(f.usage, f.usage.zoom)
  elseif cmd && K == Keys.left_bracket
    go_back!(f)
  elseif cmd && K == Keys.right_bracket
    go_forward!(f)
  elseif cmd && K == Keys.up
    enclosing!(f)
  elseif cmd && (K == Keys.down || K == Keys.o)
    open_selection!(f)
  elseif typing
    # The search field has the keyboard. Typing into it filters the folder.
    f.scroll.offset = 0px
  elseif cmd && K == Keys.z
    undo!(f)
  elseif cmd && K == Keys.a && f.mode != :columns
    f.selected = Set(e.path for e in f.order)
  elseif K == Keys.space && time() - last(f.typed) > 1
    f.quicklook = !f.quicklook && current(f) !== nothing
  elseif K in (Keys.up, Keys.down, Keys.left, Keys.right)
    move!(f, K, shift)
  elseif !cmd && haskey(LETTERS, K)
    type_select!(f, LETTERS[K])
  end
end

# --- window ------------------------------------------------------------------

"""
Open a Finder window and run it until it closes. `args` can name a folder to
start in, and `--dark` or `--light` to choose an appearance.
"""
open_finder(args) = begin
  # macOS can pass its own -options to an app it opens, so skip anything with a dash
  folders = filter(a -> !startswith(a, "-"), args)
  browser = build_finder(isempty(folders) ? homedir() : folders[1])
  browser.appearance = "--dark" in args ? :dark : "--light" in args ? :light : :system
  window = Window(browser, title="UI.jl Finder", size=(1100px, 680px))
  focus(browser)
  display(window)
end

onopen(::Finder, w::Window) = hide_titlebar!(w)

if abspath(PROGRAM_FILE) == @__FILE__
  open_finder(ARGS)
end
