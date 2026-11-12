# Markdown editor
#
# A writing app modelled on Constly. You type Markdown, and each line is drawn
# the way it will read: headings are big, **bold** is bold, tables are tables.
# The markup characters show again on the line the caret is in, so you can
# change them. A table stays a table while you type in its cells. It opens the real files on your disk, and ⌘S writes your changes
# to the file. It never writes anything until you press ⌘S.
#
# Give it a Markdown file or a folder, or it opens its own welcome page:
#
#     julia examples/28_markdown_editor.jl ~/notes/todo.md
#
# Things to try:
#   - Type. Return carries a list on. Tab and shift-Tab indent a list item.
#   - Click a cell of a table and type. Tab and shift-Tab go to the next and the
#     last cell, and Return goes down a row. Both add a row at the end.
#   - ⌘B and ⌘I make the selection bold or italic. ⌘Z and ⌘⇧Z undo and redo.
#   - Double-click selects a word, triple-click a line. ⌘-click opens a link.
#   - The button at the top left, or ⌘\, shows the other Markdown files in the
#     folder. ⌘P finds one by name.
#   - The buttons at the top right show the headings, switch between a serif and
#     a sans-serif font, and change the colours. Click the word count to count
#     characters or reading time instead.
#   - ⌘+ and ⌘- change the text size. ⌘0 puts it back.
#   - ⌘⌥I opens the layout inspector.
#
# The keyboard is read as a US one, because UI.jl gets keys rather than the
# characters they type.
#
# The example uses these UI.jl features: a `Scroll` that only builds the lines
# on screen, a `draw` method that adds the caret and selection over a node,
# italic and bold fonts by name, a colour for each part of a line of code, a
# `Stack` to float the outline and the file finder over the page, and
# `hide_titlebar!` for a window without a title bar.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" measure_text rectangle sk_color
@use Skia
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/abstract" SemanticUI WrapMode describe reuse! window_of focus
@use "../Interface/draw" ui draw ishovered cursor open_url viewport
@use "../Interface/fonts" skia_font
@use "../Interface/inspector" toggle_inspector!
@use "../Interface/window" hide_titlebar! drag_window! set_dark!
@use "../Interface/Semantic/Icon" Icon
@use "../Interface/Semantic/TextInput" TextInput
@use "./markdown_editor/markdown" Kind Line Span Cell classify spans tablecells isdivider words
@use "./markdown_editor/highlight" tokens
@use Colors: @colorant_str, RGBA, Colorant
@use InteractiveUtils: clipboard

# --- look --------------------------------------------------------------------

const SANS = isfile("/System/Library/Fonts/SFNS.ttf") ? ".SF NS" : "Helvetica"
const SERIF = "Charter"
const PLAIN = "Helvetica Neue"   # the sans-serif choice for the page. It has italics.
const MONO = "Menlo"
const SYMBOL_FONT = "Lucida Grande"

Base.@kwdef mutable struct Palette
  bg::Colorant        # the page
  ink::Colorant       # text
  dim::Colorant       # quotes, the title, the word count
  faint::Colorant     # markup characters like ** and #
  marker::Colorant    # bullets and list numbers
  line::Colorant      # table lines and rules
  chip::Colorant      # behind `code`
  chip_line::Colorant
  block::Colorant     # behind a code block
  head::Colorant      # a table's heading row
  stripe::Colorant    # every second row of a table
  accent::Colorant    # links
  select::Colorant
  panel::Colorant     # the file panel
  hover::Colorant
  active::Colorant    # the open file in the file panel
  float::Colorant     # the outline and the file finder
  shade::Colorant     # dims the window behind the file finder
  # In a code block
  comment::Colorant
  string::Colorant
  number::Colorant
  keyword::Colorant
  call::Colorant      # the name of a function being called
  type::Colorant
end

const SEPIA = Palette(bg=colorant"rgb(243,236,218)", ink=colorant"rgb(60,52,42)", dim=colorant"rgb(128,116,98)",
                      faint=colorant"rgb(176,164,140)", marker=colorant"rgb(150,136,112)",
                      line=colorant"rgb(212,203,180)", chip=colorant"rgb(234,227,206)",
                      chip_line=colorant"rgb(217,208,185)", block=colorant"rgb(236,229,209)",
                      head=colorant"rgb(234,227,207)", stripe=colorant"rgb(238,231,212)",
                      accent=colorant"rgb(156,86,38)", select=RGBA(0.72, 0.52, 0.2, 0.28),
                      panel=colorant"rgb(236,228,208)", hover=colorant"rgb(228,220,198)",
                      active=colorant"rgb(222,213,189)", float=colorant"rgb(248,243,229)",
                      shade=RGBA(0.2, 0.15, 0.05, 0.18),
                      comment=colorant"rgb(150,138,115)", string=colorant"rgb(84,116,44)",
                      number=colorant"rgb(170,98,20)", keyword=colorant"rgb(150,58,108)",
                      call=colorant"rgb(48,98,140)", type=colorant"rgb(36,116,110)")

const PAPER = Palette(bg=colorant"rgb(255,255,255)", ink=colorant"rgb(36,36,36)", dim=colorant"rgb(120,120,120)",
                      faint=colorant"rgb(178,178,178)", marker=colorant"rgb(140,140,140)",
                      line=colorant"rgb(224,224,224)", chip=colorant"rgb(243,243,243)",
                      chip_line=colorant"rgb(226,226,226)", block=colorant"rgb(246,246,246)",
                      head=colorant"rgb(244,244,244)", stripe=colorant"rgb(250,250,250)",
                      accent=colorant"rgb(22,100,210)", select=RGBA(0.26, 0.52, 0.96, 0.28),
                      panel=colorant"rgb(246,246,246)", hover=colorant"rgb(236,236,236)",
                      active=colorant"rgb(226,226,226)", float=colorant"rgb(255,255,255)",
                      shade=RGBA(0, 0, 0, 0.16),
                      comment=colorant"rgb(140,140,140)", string=colorant"rgb(30,120,60)",
                      number=colorant"rgb(180,95,0)", keyword=colorant"rgb(170,40,130)",
                      call=colorant"rgb(30,90,180)", type=colorant"rgb(0,120,130)")

const NIGHT = Palette(bg=colorant"rgb(30,30,32)", ink=colorant"rgb(222,220,214)", dim=colorant"rgb(150,148,142)",
                      faint=colorant"rgb(100,99,96)", marker=colorant"rgb(132,130,124)",
                      line=colorant"rgb(62,62,66)", chip=colorant"rgb(46,46,50)",
                      chip_line=colorant"rgb(66,66,72)", block=colorant"rgb(40,40,43)",
                      head=colorant"rgb(44,44,48)", stripe=colorant"rgb(36,36,39)",
                      accent=colorant"rgb(110,170,255)", select=RGBA(0.35, 0.58, 1.0, 0.35),
                      panel=colorant"rgb(38,38,41)", hover=colorant"rgb(52,52,56)",
                      active=colorant"rgb(62,62,68)", float=colorant"rgb(44,44,48)",
                      shade=RGBA(0, 0, 0, 0.4),
                      comment=colorant"rgb(112,112,118)", string=colorant"rgb(160,200,120)",
                      number=colorant"rgb(230,170,100)", keyword=colorant"rgb(200,130,220)",
                      call=colorant"rgb(120,170,250)", type=colorant"rgb(110,200,200)")

const THEMES = (sepia=SEPIA, paper=PAPER, night=NIGHT)
const colours = deepcopy(SEPIA)

"Draw with the colours in `p` from now on"
use!(p::Palette) = foreach(n -> setfield!(colours, n, getfield(p, n)), fieldnames(Palette))

const TOPBAR_H = 44px
const PANEL_W = 230px
const PROSE_W = 780px    # the widest the text gets, before zooming
const PAGE_X = 32px      # the least space beside the text
const PAGE_TOP = 28px
const PAGE_BOTTOM = 160px
const CHIP_X = 5px       # space inside a `code` chip, left and right of its text
const BLOCK_X = 16px     # space inside a code block, left of its text
const QUOTE_X = 18px
const CELL_X = 14px
const CELL_Y = 9px

const grow = GrowType.Grow
const clear = RGBA(0, 0, 0, 0)
fixed(w) = width(preferred=w, grow=GrowType.None)
spacer(h) = Box(width(grow=grow), height(h))
num(l) = Float64(convert(px, l).value)

label(s, size=13px; color=colours.ink, weight="") =
  Text(s, size=size, family=SANS, subfamily=weight, color=color, wrap=WrapMode.none)

# --- fonts and measuring -------------------------------------------------------

"How a run of text is drawn. A chip is the box behind `code`."
struct Face
  family::String
  style::String
  size::px
  color::Colorant
  chip::Bool
end

Face(f::Face; style=f.style, size=f.size, color=f.color, family=f.family, chip=f.chip) =
  Face(family, style, size, color, chip)

const measured = Dict{Tuple{String,String,Float32,String},px}()

"How wide `s` is in `face`. It's kept, because the same words are measured every frame."
measure(face::Face, s::AbstractString) = begin
  isempty(s) && return 0px
  length(measured) > 200_000 && empty!(measured)
  get!(measured, (face.family, face.style, Float32(num(face.size)), String(s))) do
    px(measure_text(skia_font(face.family, face.size, face.style), s)[1])
  end
end

# --- a line laid out ---------------------------------------------------------------
#
# A line of the document can wrap into several lines on screen. A Flow says
# where each run of its text goes, so the same numbers place the text, the
# caret and the selection, and turn a click back into a column.

"A run of a line's text before it's wrapped"
struct Piece
  text::String
  col::Int       # the column of its first character
  n::Int         # how many characters of the line it stands for
  face::Face
  atomic::Bool   # true when `text` isn't the line's own text, like a • for a -
  link::String
end

"A run of text placed on one line of the screen"
struct Seg
  text::String
  col::Int
  n::Int
  face::Face
  atomic::Bool
  link::String
  x::px          # from the left edge of the page's text
  w::px
end

"One line on screen"
struct VLine
  segs::Vector{Seg}
  x::px          # where its text starts
  from::Int      # the columns it covers
  to::Int
end

struct Flow
  lines::Vector{VLine}
  lh::px         # the height of each line on screen
  size::px       # the font size, which sets the caret's height
  above::px
  below::px
  kind::Kind
  raw::Bool      # true when the markup characters are showing
end

tall(f::Flow) = f.above + f.lh * length(f.lines) + f.below

"Wrap `pieces` to `limit`. Lines start at `left`, and all but the first at `hang`."
wrap(pieces, limit::px; lh, size, left=0px, hang=left, above=0px, below=0px, kind=Kind.paragraph, raw=false) = begin
  lines = VLine[]
  segs = Seg[]
  x = start = left
  flush!() = begin
    from = isempty(segs) ? (isempty(lines) ? 0 : last(lines).to) : first(segs).col
    to = isempty(segs) ? from : last(segs).col + last(segs).n
    push!(lines, VLine(segs, start, from, to))
    segs = Seg[]
    x = start = hang
  end
  # Add `text`, which is `n` characters from `col`, to the line being built
  add!(p::Piece, text, col, n) = begin
    pad = p.face.chip ? 2(CHIP_X + 1px) : 0px
    if !isempty(segs) && !p.atomic && last(segs).col + last(segs).n == col && last(segs).face === p.face && last(segs).link == p.link
      s = pop!(segs)
      joined = s.text * text
      push!(segs, Seg(joined, s.col, s.n + n, s.face, false, s.link, s.x, measure(s.face, joined) + pad))
      x = s.x + last(segs).w
    else
      w = measure(p.face, text) + pad
      push!(segs, Seg(text, col, n, p.face, p.atomic, p.link, x, w))
      x += w
    end
  end
  for p in pieces
    if p.atomic
      add!(p, p.text, p.col, p.n)
      continue
    end
    col = p.col
    for m in eachmatch(r"\S+\s*|\s+", p.text)
      word = m.match
      n = length(word)
      # Spaces at the end of a line may hang past the edge
      if x + measure(p.face, rstrip(word)) > limit && x > start
        flush!()
      end
      add!(p, String(word), col, n)
      col += n
    end
  end
  flush!()
  Flow(lines, lh, size, above, below, kind, raw)
end

"How far into `seg` the gap after its first `k` characters is"
inset(seg::Seg, k::Int) = begin
  k <= 0 && return 0px
  (seg.atomic || k >= seg.n) && return seg.w
  (seg.face.chip ? CHIP_X + 1px : 0px) + measure(seg.face, first(seg.text, k))
end

"Where column `col` is on the screen line `vl`"
xcol(vl::VLine, col::Int) = begin
  for seg in vl.segs
    col <= seg.col && return seg.x
    col <= seg.col + seg.n && return seg.x + inset(seg, col - seg.col)
  end
  isempty(vl.segs) ? vl.x : last(vl.segs).x + last(vl.segs).w
end

"The screen line that column `col` is on, and where it is on that line"
spot(f::Flow, col::Int) = begin
  for (k, vl) in enumerate(f.lines), seg in vl.segs
    col < seg.col + seg.n && return (k, xcol(vl, col))
  end
  (length(f.lines), xcol(last(f.lines), col))
end

"The column nearest to `x` on screen line `k`"
colat(f::Flow, k::Int, x::px) = begin
  vl = f.lines[k]
  isempty(vl.segs) && return vl.from
  col = vl.to
  for (i, seg) in enumerate(vl.segs)
    (x < seg.x + seg.w || i == length(vl.segs)) || continue
    if seg.atomic
      col = x < seg.x + seg.w/2 ? seg.col : seg.col + seg.n
    else
      col = seg.col + seg.n
      for c in 1:seg.n
        if x < seg.x + (inset(seg, c - 1) + inset(seg, c))/2
          col = seg.col + c - 1
          break
        end
      end
    end
    break
  end
  # The end of a wrapped line is the start of the next one, so stop a character short
  k < length(f.lines) && col >= vl.to ? max(vl.from, vl.to - 1) : col
end

# --- the document ----------------------------------------------------------------

const Pos = Tuple{Int,Int}   # a line, from 1, and a column, from 0

"An open file"
Base.@kwdef mutable struct Buffer
  path::String = ""
  lines::Vector{String} = [""]
  caret::Pos = (1, 0)
  anchor::Pos = (1, 0)                  # where the selection starts. The caret is its other end.
  undo::Vector{Any} = Any[]
  redo::Vector{Any} = Any[]
  version::Int = 0                      # changes with every edit
  saved::Int = 0                        # the version that's in the file
  typed::Float64 = 0.0                  # when a character was last typed, to undo words not letters
  offset::px = 0px                      # how far it's scrolled
  kinds::Vector{Line} = Line[]
  kinds_at::Int = -1
  words::Int = 0
  chars::Int = 0
end

const stamp = Ref(0)

load(path) = Buffer(path=path, lines=String.(split(replace(read(path, String), "\r\n" => "\n"), '\n')))

kinds(b::Buffer) = begin
  if b.kinds_at != b.version
    b.kinds = classify(b.lines)
    b.words = words(b.lines)
    b.chars = sum(length, b.lines, init=0)
    b.kinds_at = b.version
  end
  b.kinds
end

dirty(b::Buffer) = b.version != b.saved
name(b::Buffer) = isempty(b.path) ? "Untitled" : basename(b.path)
selecting(b::Buffer) = b.caret != b.anchor
"""
The two ends of the selection, first end first. A selection that covers several
lines takes the whole of each table row that it touches.
"""
selection(b::Buffer) = begin
  lo, hi = minmax(b.caret, b.anchor)
  lo[1] == hi[1] && return (lo, hi)
  ks = kinds(b)
  ks[lo[1]].kind == Kind.table && (lo = (lo[1], 0))
  ks[hi[1]].kind == Kind.table && (hi = (hi[1], length(b.lines[hi[1]])))
  (lo, hi)
end

head(s, n) = String(first(s, n))
rest(s, n) = String(chop(s, head=n, tail=0))

"The text from `lo` to `hi`"
excerpt(b::Buffer, lo::Pos, hi::Pos) = begin
  lo[1] == hi[1] && return rest(head(b.lines[lo[1]], hi[2]), lo[2])
  join([rest(b.lines[lo[1]], lo[2]); b.lines[lo[1]+1:hi[1]-1]; head(b.lines[hi[1]], hi[2])], "\n")
end

snapshot(b::Buffer) = (copy(b.lines), b.caret, b.anchor, b.version)

restore!(b::Buffer, (lines, caret, anchor, version)) = begin
  b.lines, b.caret, b.anchor, b.version = lines, caret, anchor, version
  b.typed = 0.0
end

"Replace the text from `lo` to `hi` with `new`, and put the caret after it"
edit!(b::Buffer, lo::Pos, hi::Pos, new::AbstractString; typing=false) = begin
  # Letters typed one after another undo together
  if !(typing && time() - b.typed < 1 && !isempty(b.undo))
    push!(b.undo, snapshot(b))
    length(b.undo) > 500 && popfirst!(b.undo)
  end
  empty!(b.redo)
  b.typed = typing ? time() : 0.0
  joined = head(b.lines[lo[1]], lo[2]) * new * rest(b.lines[hi[1]], hi[2])
  splice!(b.lines, lo[1]:hi[1], String.(split(joined, '\n')))
  parts = split(new, '\n')
  b.caret = b.anchor = (lo[1] + length(parts) - 1, length(parts) == 1 ? lo[2] + length(new) : length(last(parts)))
  b.version = (stamp[] += 1)
  b
end

undo!(b::Buffer) = isempty(b.undo) || (push!(b.redo, snapshot(b)); restore!(b, pop!(b.undo)))
redo!(b::Buffer) = isempty(b.redo) || (push!(b.undo, snapshot(b)); restore!(b, pop!(b.redo)))

save!(b::Buffer) = begin
  isempty(b.path) && return
  write(b.path, join(b.lines, "\n"))
  b.saved = b.version
end

# --- the app -------------------------------------------------------------------------

"One block of the page: a line of the document, or a table drawn as a table"
struct Item
  first::Int     # the lines of the document it shows
  last::Int
  top::px        # from the top of the page's text
  tall::px
  content::Any   # a Flow or a Grid
end

"A table laid out"
struct Grid
  rows::Vector{Int}            # the line of the document each row comes from
  widths::Vector{px}
  heights::Vector{px}
  cells::Vector{Vector{Cell}}  # where each cell's text is in its line
  flows::Vector{Vector{Flow}}  # one for each column, even where a row has no cell
end

@def mutable struct Editor <: SemanticUI
  buf::Buffer = Buffer()
  buffers::Dict{String,Buffer} = Dict{String,Buffer}()
  folder::String = ""
  files::Vector{String} = String[]      # the Markdown files in the folder
  panel::Bool = false                   # is the file panel showing?
  theme::Symbol = :sepia
  applied::Symbol = :none               # the theme the window was last told about
  serif::Bool = true
  zoom::Float64 = 1.0
  stat::Symbol = :words                 # what the count at the top right counts
  popup::Symbol = :none                 # :outline or :finder when one is open
  picked::Int = 1                       # the file the finder will open
  scroll::Scroll = Scroll(width(grow=grow), height(grow=grow))
  files_scroll::Scroll = Scroll(width(grow=grow), height(grow=grow))
  outline_scroll::Scroll = Scroll(width(grow=grow), height(grow=grow))
  nodes::Dict{Any,Any} = Dict{Any,Any}()   # the parts of the window, kept between frames
  flows::Dict{Any,Any} = Dict{Any,Any}()
  layout::Vector{Item} = Item[]
  shown::UnitRange{Int} = 1:0           # the items that were built for the last frame
  width::px = PROSE_W                   # how wide the text is
  origin::Tuple{px,px} = (0px, 0px)     # where the page's text was last drawn in the window
  goal::Union{Nothing,px} = nothing     # where ↑ and ↓ try to keep the caret
  reveal::Bool = false                  # scroll to the caret before the next frame
  blink::Float64 = time()
  clicked::Tuple{Float64,Pos,Int} = (0.0, (0, 0), 0)
  size::Tuple{px,px} = (1100px, 800px)  # the window's size, until there is a window to ask
end

@def mutable struct TopBar <: SemanticUI end
@def mutable struct Page <: SemanticUI end       # the scrolling area around the text
@def mutable struct Document <: SemanticUI end   # the text itself
@def mutable struct Backdrop <: SemanticUI end   # catches clicks outside a popup
@def mutable struct FinderInput <: SemanticUI end
@def mutable struct ToolButton <: SemanticUI
  icon::String = ""
  action::Symbol = :none
end
@def mutable struct Count <: SemanticUI end
@def mutable struct FileRow <: SemanticUI
  path::String = ""
  finder::Int = 0    # its place in the file finder's list, or 0 in the file panel
end
@def mutable struct OutlineRow <: SemanticUI
  line::Int = 0
  level::Int = 1
  title::String = ""
end

editor(node) = begin
  while !(node isa Editor)
    node = node.parent
  end
  node
end

"A node that belongs to `e` and is kept for as long as `e` is"
own!(e, node) = (node.parent === nothing && setfield!(node, :parent, e); node)
node!(make, e, key) = get!(() -> own!(e, make()), e.nodes, key)

const MARKDOWN = (".md", ".markdown", ".mdx")
ismarkdown(path) = lowercase(splitext(path)[2]) in MARKDOWN

"Open the editor on a file, or on the first Markdown file in a folder"
build_editor(path) = begin
  path = abspath(expanduser(path))
  e = Editor()
  e.nodes[:input] = own!(e, TextInput(placeholder="Find a file", font_family=SANS, font_size=15px,
                                      look=(_, text) -> Row(width(grow=grow), height(grow=grow), clip=true, text)))
  if isdir(path)
    e.folder = path
    e.panel = true
    list_files!(e)
    isempty(e.files) || open!(e, e.files[1])
  else
    open!(e, path)
  end
  e
end

list_files!(e) = begin
  names = isdir(e.folder) ? readdir(e.folder) : String[]
  e.files = [joinpath(e.folder, n) for n in sort!(names, by=lowercase) if ismarkdown(n) && !startswith(n, '.')]
end

"Show the file at `path`. A file that's already open keeps its changes."
open!(e, path) = begin
  e.buf.offset = e.scroll.offset
  e.buf = get!(e.buffers, path) do
    isfile(path) ? load(path) : Buffer(path=path)
  end
  if e.folder != dirname(path)
    e.folder = dirname(path)
    list_files!(e)
  end
  e.scroll.offset = e.buf.offset
  e.popup = :none
  e.goal = nothing
  w = window_of(e)
  w === nothing || focus(e)
  e
end

window_size(e) = something(viewport(e), e.size)
input(e) = e.nodes[:input]::TextInput

# --- faces -----------------------------------------------------------------------------

body(e) = Face(e.serif ? SERIF : PLAIN, "", 17px * e.zoom, colours.ink, false)
const HEADINGS = (2.1, 1.75, 1.4, 1.2, 1.05, 1.0)

"The face a line's plain text is drawn in"
face(e, line::Line) = begin
  b = body(e)
  k = line.kind
  k == Kind.heading ? Face(b, style="Bold", size=b.size * HEADINGS[line.level]) :
  k == Kind.blockquote ? Face(b, style="Italic", color=colours.dim) :
  k in (Kind.code, Kind.fence, Kind.table, Kind.rule) ? Face(b, family=MONO, size=b.size * 0.86) : b
end

"The face for one span of a line whose plain text is drawn in `base`"
face(base::Face, s::Span) = begin
  s.markup && return Face(base, color=colours.faint)
  s.code && return Face(MONO, "", base.size * 0.86, base.color, true)
  bold = s.bold || occursin("Bold", base.style)
  italic = s.italic || occursin("Italic", base.style)
  style = bold && italic ? "Bold Italic" : bold ? "Bold" : italic ? "Italic" : ""
  Face(base, style=style, color=!isempty(s.link) ? colours.accent : s.strike ? colours.faint : base.color)
end

piece(text, col, face; atomic=false, n=length(text), link="") = Piece(text, col, n, face, atomic, link)

"The runs of text that line `text` is drawn as. With `raw`, the markup shows."
pieces(e, text::String, line::Line, raw::Bool) = begin
  base = face(e, line)
  out = Piece[]
  k = line.kind
  if k == Kind.code
    # Each part of a line of code has its own colour, and comments slant
    for t in tokens(text, line.lang)
      colour = t.kind == :plain ? base.color : getfield(colours, t.kind)
      push!(out, piece(t.text, t.col, Face(base, color=colour, style=t.kind == :comment ? "Italic" : "")))
    end
    return out
  elseif k in (Kind.fence, Kind.table, Kind.rule)
    k == Kind.fence && !raw && return out
    isempty(text) || push!(out, piece(text, 0, k == Kind.table ? base : Face(base, color=colours.faint)))
    return out
  end
  lead = head(text, line.prefix)
  if k == Kind.bullet || k == Kind.ordered
    line.level > 0 && push!(out, piece(head(lead, line.level), 0, base))
    mark = Face(base, style="Bold", color=colours.marker)
    if k == Kind.bullet && !raw
      push!(out, piece("•  ", line.level, mark, atomic=true, n=line.prefix - line.level))
    else
      push!(out, piece(rest(lead, line.level), line.level, mark))
    end
  elseif k == Kind.paragraph
    isempty(lead) || push!(out, piece(lead, 0, base))
  elseif raw && !isempty(lead)
    push!(out, piece(lead, 0, Face(base, color=colours.faint)))
  end
  for s in spans(rest(text, line.prefix), line.prefix)
    s.markup && !raw && continue
    symbols!(out, s.text, s.col, face(base, s), s.link)
  end
  out
end

# The page's fonts have no ⌘ or arrows, so those characters are drawn in one that does
const SYMBOLS = r"[⌘⌥⇧⌃⏎⇥←→↑↓]+"

"Add `text` to `out`, with its keyboard symbols in a font that has them"
symbols!(out, text, col, face, link="") = begin
  at = 1
  add(part, symbol) = isempty(part) ||
    (push!(out, piece(String(part), col, symbol ? Face(face, family=SYMBOL_FONT, style="") : face; link)); col += length(part))
  for m in eachmatch(SYMBOLS, text)
    add(SubString(text, at, prevind(text, m.offset)), false)
    add(m.match, true)
    at = m.offset + ncodeunits(m.match)
  end
  add(SubString(text, at), false)
  out
end

"The first and last line of the code block that line `i` is in, with the lines that open and close it"
codeblock(b::Buffer, i::Int) = begin
  ks = kinds(b)
  s = t = i
  while s > 1 && !(ks[s].kind == Kind.fence && ks[s].level == 0); s -= 1 end
  while t < length(ks) && !(ks[t].kind == Kind.fence && ks[t].level == 1 && t > s); t += 1 end
  (s, t)
end

"True when the caret or the other end of the selection is in the code block that line `i` is in"
incode(b::Buffer, i::Int) = begin
  s, t = codeblock(b, i)
  s <= b.caret[1] <= t || s <= b.anchor[1] <= t
end

"True when line `i` shows its markup: it has the caret, and the selection doesn't reach another line"
israw(b::Buffer, i::Int) = i == b.caret[1] == b.anchor[1]

"Lay out line `i` of the document"
flow(e, i::Int, raw::Bool=israw(e.buf, i)) = begin
  text, line = e.buf.lines[i], kinds(e.buf)[i]
  # The lines that open and close a code block only show while the caret is in the block
  line.kind == Kind.fence && (raw = incode(e.buf, i))
  length(e.flows) > 4000 && empty!(e.flows)
  get!(e.flows, (text, line, raw)) do
    base = face(e, line)
    ps = pieces(e, text, line, raw)
    k = line.kind
    # A hidden ``` line leaves a little room at the top or bottom of its block
    lh = k == Kind.heading ? base.size * 1.35 : body(e).size * (k == Kind.fence && !raw ? 0.6 : 1.65)
    left = k in (Kind.code, Kind.fence) ? BLOCK_X : k == Kind.blockquote ? QUOTE_X : 0px
    # Lines that a list item wraps onto start under its text, not under its bullet
    hang = k in (Kind.bullet, Kind.ordered) ? sum(p -> measure(p.face, p.text), ps[1:min(end, line.level > 0 ? 2 : 1)], init=0px) : left
    above = k == Kind.heading ? lh * 0.3 : 0px
    below = k == Kind.heading ? lh * 0.12 : 0px
    wrap(ps, e.width; lh, size=base.size, left, hang, above, below, kind=k, raw)
  end
end

"Forget every layout, after something that changes how all the text is drawn"
restyle!(e) = (empty!(e.flows); e.reveal = true; e)

# --- tables ----------------------------------------------------------------------------
#
# A table is a line of cells, a line of dashes, then more lines of cells. It's
# drawn as a grid, and the caret moves from cell to cell. The line of dashes
# isn't drawn. If the caret gets onto it, the table shows as plain lines.

"The first and last line of the table that line `i` is part of, or nothing"
table(b::Buffer, i::Int) = begin
  ks = kinds(b)
  ks[i].kind == Kind.table || return nothing
  s = t = i
  while s > 1 && ks[s-1].kind == Kind.table; s -= 1 end
  while t < length(ks) && ks[t+1].kind == Kind.table; t += 1 end
  t > s && isdivider(b.lines[s+1]) ? (s, t) : nothing
end

"The lines of a table that are rows of cells"
tablerows((s, t)) = [s; s+2:t]

"The cells of the row that `p` is in, when that row is drawn in a grid"
rowcells(b::Buffer, p::Pos) = begin
  run = table(b, p[1])
  (run === nothing || p[1] == run[1] + 1) ? Cell[] : tablecells(b.lines[p[1]])
end

within(c::Cell, col::Int) = c.lo <= col <= c.limit

"The cell that `p` is in, or nothing"
cellat(b::Buffer, p::Pos) = begin
  cs = rowcells(b, p)
  i = findfirst(c -> within(c, p[2]), cs)
  i === nothing ? nothing : cs[i]
end

"Which of `cs` column `col` is in, or is nearest to"
nearest(cs, col::Int) = argmin(i -> within(cs[i], col) ? 0 : min(abs(col - cs[i].lo), abs(col - cs[i].limit)), eachindex(cs))

"""
Where the caret goes when it's sent to `p`. In a table that's the same place
if `p` is in a cell. Otherwise it's the next cell in the direction `by`, or the
nearest cell when `by` is 0.
"""
settle(b::Buffer, p::Pos, by::Int=0) = begin
  run = table(b, p[1])
  run === nothing && return p
  s, t = run
  i, col = p
  if i == s + 1
    # The line of dashes. Step over it, unless that's where a click put the caret.
    by == 0 && return p
    j = by < 0 ? s : s + 2
    return j > t ? (t < length(b.lines) ? (t + 1, 0) : p) : settle(b, (j, col))
  end
  cs = tablecells(b.lines[i])
  (isempty(cs) || any(c -> within(c, col), cs)) && return p
  rows = tablerows(run)
  r = findfirst(==(i), rows)
  if by < 0
    c = findlast(c -> c.limit < col, cs)
    c === nothing || return (i, cs[c].hi)
    r > 1 && return row_edge(b, rows[r-1], 1)
    s > 1 ? line_end(b, s - 1) : (i, cs[1].lo)
  elseif by > 0
    c = findfirst(c -> c.lo > col, cs)
    c === nothing || return (i, cs[c].lo)
    r < length(rows) && return row_edge(b, rows[r+1], -1)
    t < length(b.lines) ? (t + 1, 0) : (i, cs[end].hi)
  else
    c = cs[nearest(cs, col)]
    (i, clamp(col, c.lo, c.limit))
  end
end

"The start of the first cell of row `i`, or with `by` of 1 the end of its last cell"
row_edge(b::Buffer, i::Int, by::Int) = begin
  cs = tablecells(b.lines[i])
  isempty(cs) ? (i, 0) : by < 0 ? (i, cs[1].lo) : (i, cs[end].hi)
end

"The runs of text in a cell that shows columns `lo` to `hi` of `text`"
cellpieces(text::String, lo::Int, hi::Int, base::Face, raw::Bool) = begin
  out = Piece[]
  for s in spans(rest(head(text, hi), lo), lo)
    s.markup && !raw && continue
    symbols!(out, s.text, s.col, face(base, s), s.link)
  end
  out
end

"Lay out the table in lines `from` to `to` of the document"
grid(e, from::Int, to::Int) = begin
  b = e.buf
  caret = from <= b.caret[1] <= to ? b.caret : nothing
  get!(e.flows, (:grid, b.lines[from:to], caret)) do
    base = Face(body(e), size=body(e).size * 0.94)
    lh = base.size * 1.5
    rows = tablerows((from, to))
    cells = [tablecells(b.lines[i]) for i in rows]
    ncols = max(1, maximum(length, cells))
    parts = map(enumerate(rows)) do (r, i)
      map(1:ncols) do c
        c <= length(cells[r]) || return Piece[]
        cell = cells[r][c]
        # The cell with the caret shows its markup, and the spaces typed after its text
        active = caret !== nothing && caret[1] == i && within(cell, caret[2])
        cellpieces(b.lines[i], cell.lo, active ? max(cell.hi, caret[2]) : cell.hi,
                   r == 1 ? Face(base, style="Bold") : base, active)
      end
    end
    # Each column gets room in proportion to its longest cell
    natural = [maximum(row -> sum(p -> measure(p.face, p.text), row[c], init=0px), parts, init=0px) + 2CELL_X for c in 1:ncols]
    natural = [clamp(w, 60px, e.width * 0.75) for w in natural]
    space = e.width - 1px * (ncols + 1)
    widths = natural .* (num(space) / num(sum(natural)))
    flows = [[wrap(row[c], widths[c] - 2CELL_X; lh, size=base.size, left=CELL_X) for c in 1:ncols] for row in parts]
    heights = [maximum(f -> tall(f), row) + 2CELL_Y for row in flows]
    Grid(rows, widths, heights, cells, flows)
  end
end

const TABLE_GAP = 8px   # above and below a table
tall(g::Grid) = sum(g.heights) + 1px * (length(g.heights) + 1) + 2TABLE_GAP

"Where the text of row `r`, column `c` starts, from the top left of the table's item"
cell_origin(g::Grid, r::Int, c::Int) =
  (1px * c + sum(g.widths[1:c-1], init=0px),
   TABLE_GAP + 1px * r + sum(g.heights[1:r-1], init=0px) + (g.heights[r] - tall(g.flows[r][c]))/2)

"The column in `cell` nearest to `x` on line `k` of its flow"
cellcol(f::Flow, k::Int, x::px, cell::Cell) =
  isempty(f.lines[k].segs) ? cell.lo : clamp(colat(f, k, x), cell.lo, cell.limit)

"The row and column of `g` that holds the caret at `p`, or nothing"
gridcell(g::Grid, p::Pos) = begin
  r = findfirst(==(p[1]), g.rows)
  (r === nothing || isempty(g.cells[r])) && return nothing
  (r, nearest(g.cells[r], p[2]))
end

# --- the page's layout ---------------------------------------------------------------

"Work out what the page shows and how tall each part is"
layout!(e) = begin
  b = e.buf
  ks = kinds(b)
  w, _ = window_size(e)
  width = clamp(w - (e.panel ? PANEL_W : 0px) - 2PAGE_X, 240px, PROSE_W * e.zoom)
  width == e.width || (e.width = width; empty!(e.flows))
  items = Item[]
  top = 0px
  i = 1
  n = length(b.lines)
  while i <= n
    j = i
    if ks[i].kind == Kind.table
      while j < n && ks[j+1].kind == Kind.table
        j += 1
      end
    end
    # A table needs its line of dashes. It shows as plain lines while the caret is on that line.
    if j > i && isdivider(b.lines[i+1]) && b.caret[1] != i + 1 && b.anchor[1] != i + 1
      content = grid(e, i, j)
      push!(items, Item(i, j, top, tall(content), content))
      top += tall(content)
      i = j + 1
    else
      content = flow(e, i)
      push!(items, Item(i, i, top, tall(content), content))
      top += tall(content)
      i += 1
    end
  end
  e.layout = items
end

"The item that shows line `i`"
item(e, i::Int) = e.layout[something(findfirst(it -> it.first <= i <= it.last, e.layout), length(e.layout))]

"Scroll so the caret is on screen"
reveal!(e) = begin
  it = item(e, e.buf.caret[1])
  top, bottom = it.top, it.top + it.tall
  if it.content isa Flow
    k, _ = spot(it.content, e.buf.caret[2])
    top = it.top + it.content.above + it.content.lh * (k - 1)
    bottom = top + it.content.lh
  end
  scroll_into_view!(e.scroll, PAGE_TOP + top - 30px, PAGE_TOP + bottom + 40px)
end

# --- drawing the text -----------------------------------------------------------------

describe(seg::Seg) = begin
  f = seg.face
  t = Text(seg.text, size=f.size, family=f.family, subfamily=f.style, color=f.color, wrap=WrapMode.none)
  # A Text on its own would take a share of the spare room in its row
  f.chip || return Box(fixed(seg.w), Alignment.Start, t)
  Box(fixed(seg.w), height(f.size * 1.5), padding(CHIP_X, 0px), radius(4px), background(colours.chip), border(1px, :solid, colours.chip_line), t)
end

"The lines of a Flow, as rows of text. `edge` is the width of a border on its left."
rows(f::Flow, edge=0px) =
  [Row(width(grow=grow), height(f.lh), padding(0px, 0px, 0px, vl.x - edge), clip=true, map(describe, vl.segs)...) for vl in f.lines]

describe(e::Editor, it::Item) = describe(e, it, it.content)

describe(e::Editor, it::Item, f::Flow) = begin
  k = f.kind
  if k == Kind.rule && !f.raw
    return Box(width(grow=grow), height(tall(f)), Box(width(grow=grow), height(1px), background(colours.line)))
  end
  edge = k == Kind.blockquote ? 3px : 0px
  col = Column(width(grow=grow), Alignment.Start, padding(f.above, 0px, f.below, 0px), rows(f, edge)...)
  if k == Kind.code || k == Kind.fence
    col.background = background(colours.block)
  elseif k == Kind.blockquote
    col.border = border(edge, :solid, colours.line)[:left]
  end
  col
end

describe(e::Editor, it::Item, g::Grid) = begin
  line = border(1px, :solid, colours.line; between=true)
  table = Column(width(grow=grow), Alignment.Start, line, name="Table",
    [Row(width(grow=grow), height(g.heights[r]), Alignment.Start, line[:between],
         background(r == 1 ? colours.head : iseven(r) ? colours.bg : colours.stripe),
       [Column(fixed(g.widths[c]), height(grow=grow), Alignment.Start, justify=Alignment.Center, rows(g.flows[r][c])...)
        for c in eachindex(g.widths)]...)
     for r in eachindex(g.rows)]...)
  Box(width(grow=grow), padding(0px, TABLE_GAP), table)
end

describe(d::Document) = begin
  e = editor(d)
  items = e.layout
  total = isempty(items) ? 0px : last(items).top + last(items).tall
  _, h = window_size(e)
  # Only the lines on screen, and a few either side, are built
  from, to = e.scroll.offset - PAGE_TOP - 200px, e.scroll.offset + h + 200px
  lo = something(findfirst(it -> it.top + it.tall >= from, items), length(items))
  hi = something(findlast(it -> it.top <= to, items), lo)
  e.shown = lo:hi
  Column(fixed(e.width), Alignment.Start, name="Document",
    spacer(items[lo].top),
    [describe(e, it) for it in items[lo:hi]]...,
    spacer(total - items[hi].top - items[hi].tall))
end

cursor(::Document) = :ibeam

describe(p::Page) = begin
  e = editor(p)
  reuse!(e.scroll,
    Row(width(grow=grow), Alignment.Start, justify=Alignment.Center, padding(PAGE_TOP, PAGE_X, PAGE_BOTTOM, PAGE_X),
      node!(Document, e, :document)))
end

"The part of line `i` that's selected, as columns, and whether the selection goes on past it"
selected(b::Buffer, i::Int) = begin
  lo, hi = selection(b)
  (lo[1] <= i <= hi[1] && lo != hi) || return nothing
  (i == lo[1] ? lo[2] : 0, i == hi[1] ? hi[2] : length(b.lines[i]), i < hi[1])
end

const Rect = NTuple{4,Float64}   # left, top, right and bottom, in px

"""
The boxes that cover the selected part of each line of `f`, whose top left
corner is at (x, y). The first and last boxes take in the space above and below
the lines, so the boxes of one line of the document meet those of the next.
With `margin`, a box that starts at the start of its line also takes in the
space to the left of the text, like the inset of a code block. That keeps the
left edge of the selection straight from one kind of line to the next.
"""
marks(f::Flow, x, y, (from, to, more); margin=true) = begin
  out = Rect[]
  n = length(f.lines)
  for (k, vl) in enumerate(f.lines)
    (from <= vl.to && to >= vl.from) || continue
    x1 = from > vl.from ? xcol(vl, from) : margin ? 0px : vl.x
    x2 = xcol(vl, min(to, vl.to))
    # A little extra shows that the end of the line is selected too
    (to > vl.to || (more && k == n)) && (x2 += 7px)
    x2 > x1 || continue
    top = k == 1 ? 0px : f.above + f.lh * (k - 1)
    bottom = f.above + f.lh * k + (k == n ? f.below : 0px)
    push!(out, (num(x + x1), num(y + top), num(x + x2), num(y + bottom)))
  end
  out
end

const SELECTION_RADIUS = 4.0

"""
Fill the selection. Boxes that sit on top of each other are joined into one
shape, and every corner of that shape is rounded, the ones that point in as
well as the ones that point out.
"""
fill_selection(ctx, rects::Vector{Rect}) = begin
  isempty(rects) && return
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(colours.select))
  from = 1
  for i in 2:length(rects)+1
    # A box joins the one above it when they touch and share some width
    joined = i <= length(rects) && abs(rects[i][2] - rects[i-1][4]) < 1 &&
             rects[i][1] < rects[i-1][3] && rects[i][3] > rects[i-1][1]
    joined && continue
    outline = rounded(corners(rects[from:i-1]), SELECTION_RADIUS)
    Skia.sk_canvas_draw_path(ctx, outline, paint)
    Skia.sk_path_delete(outline)
    from = i
  end
  Skia.sk_paint_delete(paint)
end

"The corners of the shape made by a stack of boxes: down its right side, then back up its left"
corners(rects) = begin
  points = NTuple{2,Float64}[]
  add(p) = (isempty(points) || points[end] != p) && push!(points, p)
  top = rects[1][2]
  for (l, t, r, b) in rects
    add((r, top)); add((r, b))
    top = b
  end
  for (i, (l, t, r, b)) in Iterators.reverse(enumerate(rects))
    add((l, b)); add((l, i == 1 ? t : rects[i-1][4]))
  end
  points
end

"A Skia path around `points`, with each corner rounded by up to `radius`"
rounded(points, radius) = begin
  path = Skia.sk_path_new()
  n = length(points)
  for i in 1:n
    before, corner, after = points[mod1(i - 1, n)], points[i], points[mod1(i + 1, n)]
    d1, d2 = hypot((before .- corner)...), hypot((after .- corner)...)
    # A short edge has room for less of a curve at each end
    r = min(radius, d1 / 2, d2 / 2)
    a = corner .+ (before .- corner) .* (r / max(d1, 1e-6))
    b = corner .+ (after .- corner) .* (r / max(d2, 1e-6))
    i == 1 ? Skia.sk_path_move_to(path, Float32(a[1]), Float32(a[2])) : Skia.sk_path_line_to(path, Float32(a[1]), Float32(a[2]))
    # A conic with this weight is a quarter of a circle
    Skia.sk_path_conic_to(path, Float32(corner[1]), Float32(corner[2]), Float32(b[1]), Float32(b[2]), Float32(sqrt(0.5)))
  end
  Skia.sk_path_close(path)
  path
end

"Draw the caret at column `col` of `f`, whose top left corner is at (x, y)"
caret(ctx, e, f::Flow, x, y, col) = begin
  w = window_of(e)
  (w !== nothing && w.focus === e) || return
  since = time() - e.blink
  (since < 0.5 || mod(since - 0.5, 1.0) >= 0.5) || return
  k, cx = spot(f, col)
  high = f.size * 1.25
  rectangle(ctx, x + cx - 0.75px, y + f.above + f.lh * (k - 1) + (f.lh - high)/2, 1.5px, high, background=colours.ink, border=0px)
end

# The caret and the selection are drawn over the text, once it has been placed
draw(ctx, size, ui::ConcreteRect, d::Document) = begin
  e = editor(d)
  b = e.buf
  e.origin = (ui.left, ui.top)
  # The selection goes under the caret, as one shape for each run of lines that touch
  rects = Rect[]
  for it in e.layout[e.shown]
    top = ui.top + it.top
    if it.content isa Grid
      g = it.content
      if b.caret[1] != b.anchor[1]
        # A selection that covers several lines takes each row whole
        lo, hi = selection(b)
        y = top + TABLE_GAP
        lo[1] < it.first && hi[1] >= it.first && push!(rects, (num(ui.left), num(top), num(ui.left + 7px), num(y)))
        for (r, i) in enumerate(g.rows)
          h = g.heights[r] + (r == length(g.rows) ? 2px : 1px)
          lo[1] <= i <= hi[1] && push!(rects, (num(ui.left), num(y), num(ui.left + e.width), num(y + h)))
          y += h
        end
        hi[1] > it.last && push!(rects, (num(ui.left), num(y), num(ui.left + 7px), num(y + TABLE_GAP)))
        continue
      end
      for (r, i) in enumerate(g.rows), (c, cell) in enumerate(g.cells[r])
        sel = selected(b, i)
        (sel !== nothing && sel[1] < cell.limit && sel[2] > cell.lo) || continue
        x, y = cell_origin(g, r, c)
        fill_selection(ctx, marks(g.flows[r][c], ui.left + x, top + y, (max(sel[1], cell.lo), min(sel[2], cell.limit), false), margin=false))
      end
    else
      sel = selected(b, it.first)
      sel === nothing || append!(rects, marks(it.content, ui.left, top, sel))
    end
  end
  fill_selection(ctx, rects)
  for it in e.layout[e.shown]
    top = ui.top + it.top
    if it.content isa Grid
      g = it.content
      at = gridcell(g, b.caret)
      for (r, i) in enumerate(g.rows), (c, cell) in enumerate(g.cells[r])
        x, y = cell_origin(g, r, c)
        at == (r, c) && caret(ctx, e, g.flows[r][c], ui.left + x, top + y, b.caret[2])
      end
      continue
    end
    it.first == b.caret[1] && caret(ctx, e, it.content::Flow, ui.left, top, b.caret[2])
  end
end

# --- the mouse on the page --------------------------------------------------------------

"The place in the document under a point in the window"
locate(e, (x, y)) = begin
  dx, dy = x - e.origin[1], y - e.origin[2]
  items = e.layout
  it = items[something(findlast(it -> it.top <= dy, items), 1)]
  if it.content isa Grid
    g = it.content
    # The row and the column under the point
    r = something(findfirst(r -> dy < it.top + cell_origin(g, r, 1)[2] + g.heights[r], eachindex(g.rows)), length(g.rows))
    c = something(findlast(c -> dx >= cell_origin(g, r, c)[1], eachindex(g.widths)), 1)
    cells = g.cells[r]
    isempty(cells) && return line_end(e.buf, g.rows[r])
    # A row can have fewer cells than the table has columns
    c = min(c, length(cells))
    f = g.flows[r][c]
    x, y = cell_origin(g, r, c)
    k = clamp(floor(Int, num(dy - it.top - y) / num(f.lh)) + 1, 1, length(f.lines))
    return (g.rows[r], cellcol(f, k, dx - x, cells[c]))
  end
  f = it.content::Flow
  k = clamp(floor(Int, num(dy - it.top - f.above) / num(f.lh)) + 1, 1, length(f.lines))
  (it.first, colat(f, k, dx))
end

"The link under a point in the window, or nothing"
link_at(e, pos) = begin
  line, col = locate(e, pos)
  it = item(e, line)
  it.content isa Flow || return nothing
  for vl in it.content.lines, seg in vl.segs
    seg.col <= col < seg.col + seg.n && !isempty(seg.link) && return seg.link
  end
  nothing
end

isword(c::Char) = isletter(c) || isdigit(c) || c == '_' || c == '\''

"The columns of the word around column `col` of `line`"
word_at(line::String, col::Int) = begin
  chars = collect(line)
  lo = hi = clamp(col, 0, length(chars))
  while lo > 0 && isword(chars[lo]); lo -= 1 end
  while hi < length(chars) && isword(chars[hi+1]); hi += 1 end
  (lo, hi)
end

held(node, key) = (w = window_of(node); w !== nothing && key in w.keys)

"The caret moved or the text changed, so show the caret"
touch!(e; keep_goal=false) = begin
  e.blink = time()
  e.reveal = true
  keep_goal || (e.goal = nothing)
  e
end

press!(e, pos) = begin
  b = e.buf
  focus(e)
  e.popup = :none
  if held(e, Keys.cmd)
    url = link_at(e, pos)
    url === nothing || return open_url(url)
  end
  at = settle(b, locate(e, pos))
  t, before, count = e.clicked
  count = time() - t < 0.4 && before == at ? count % 3 + 1 : 1
  e.clicked = (time(), at, count)
  if count == 2
    lo, hi = word_at(b.lines[at[1]], at[2])
    b.anchor, b.caret = (at[1], lo), (at[1], hi)
  elseif count == 3
    # Three clicks select the line, or in a table the cell
    cell = cellat(b, at)
    lo, hi = cell === nothing ? (0, length(b.lines[at[1]])) : (cell.lo, cell.hi)
    b.anchor, b.caret = (at[1], lo), (at[1], hi)
  else
    b.caret = at
    held(e, Keys.shft) || (b.anchor = at)
  end
  touch!(e)
end

drag!(e, pos) = begin
  held(e, Keys.mouse_left) && e.clicked[3] == 1 || return
  at = settle(e.buf, locate(e, pos))
  at == e.buf.caret && return
  e.buf.caret = at
  touch!(e)
end

onkey(d::Document, ev::KeyPress{Keys.mouse_left}) = press!(editor(d), ev.window.mouse)
onkey(p::Page, ev::KeyPress{Keys.mouse_left}) = press!(editor(p), ev.window.mouse)
onmouse(d::Document, ev::MouseMove) = drag!(editor(d), ev.position)
onmouse(p::Page, ev::MouseMove) = drag!(editor(p), ev.position)

# --- editing -----------------------------------------------------------------------------

const TYPED = Dict{Keys,Tuple{Char,Char}}()   # what each key types, alone and with shift
for c in 'a':'z'
  TYPED[getproperty(Keys, Symbol(c))] = (c, uppercase(c))
end
for (d, c) in zip(0:9, ")!@#\$%^&*(")
  TYPED[getproperty(Keys, Symbol(d))] = (Char('0' + d), c)
end
for (key, pair) in (:tilde => ('`', '~'), :minus => ('-', '_'), :equal => ('=', '+'), :left_bracket => ('[', '{'),
                    :right_bracket => (']', '}'), :semicolon => (';', ':'), :apostrophe => ('\'', '"'),
                    :comma => (',', '<'), :period => ('.', '>'), :slash => ('/', '?'), :backslash => ('\\', '|'),
                    :space => (' ', ' '))
  TYPED[getproperty(Keys, key)] = pair
end

"Put `new` where the selection is, or at the caret"
type!(e, new; typing=false) = begin
  b = e.buf
  cell = cellat(b, b.caret)
  if cell !== nothing && b.caret[1] == b.anchor[1]
    # In a row of a table, typing only ever changes the cell the caret is in
    lo, hi = selection(b)
    (within(cell, lo[2]) && within(cell, hi[2])) || (b.anchor = b.caret)
    new = replace(new, '\n' => ' ')
  end
  lo, hi = selection(b)
  edit!(b, lo, hi, new; typing)
  touch!(e)
end

line_end(b, i) = (i, length(b.lines[i]))

"The place one character before or after `p`"
beside(b::Buffer, (i, col)::Pos, by::Int) =
  by < 0 ? (col > 0 ? (i, col - 1) : i > 1 ? line_end(b, i - 1) : (i, col)) :
           (col < length(b.lines[i]) ? (i, col + 1) : i < length(b.lines) ? (i + 1, 0) : (i, col))

"The place one word before or after `p`"
word_step(b::Buffer, p::Pos, by::Int) = begin
  i, col = p
  chars = collect(b.lines[i])
  (by < 0 ? col == 0 : col == length(chars)) && return beside(b, p, by)
  if by < 0
    while col > 0 && !isword(chars[col]); col -= 1 end
    while col > 0 && isword(chars[col]); col -= 1 end
  else
    while col < length(chars) && !isword(chars[col+1]); col += 1 end
    while col < length(chars) && isword(chars[col+1]); col += 1 end
  end
  (i, col)
end

"The place one line up or down the screen from the caret"
vertical(e, by::Int) = begin
  b = e.buf
  i, col = b.caret
  it = item(e, i)
  at = it.content isa Grid ? gridcell(it.content, b.caret) : nothing
  at === nothing || return vertical(e, it, at, by)
  f = flow(e, i)
  k, x = spot(f, col)
  x = e.goal = something(e.goal, x)
  1 <= k + by <= length(f.lines) && return (i, colat(f, k + by, x))
  j = i + by
  j < 1 && return (1, 0)
  j > length(b.lines) && return line_end(b, i)
  f = flow(e, j, true)
  (j, colat(f, by < 0 ? length(f.lines) : 1, x))
end

"The place one line up or down from the caret, which is in row `r`, column `c` of a table"
vertical(e, it::Item, (r, c), by::Int) = begin
  b = e.buf
  g = it.content::Grid
  f = g.flows[r][c]
  k, x = spot(f, b.caret[2])
  x = e.goal = something(e.goal, x)
  1 <= k + by <= length(f.lines) && return (b.caret[1], cellcol(f, k + by, x, g.cells[r][c]))
  r += by
  if r < 1
    return it.first > 1 ? line_end(b, it.first - 1) : b.caret
  elseif r > length(g.rows)
    # ↓ on the last row of a table at the end of the document starts a line below it
    it.last == length(b.lines) && edit!(b, line_end(b, it.last), line_end(b, it.last), "\n")
    return (it.last + 1, 0)
  end
  isempty(g.cells[r]) && return (g.rows[r], 0)
  c = min(c, length(g.cells[r]))
  f = g.flows[r][c]
  (g.rows[r], cellcol(f, by < 0 ? length(f.lines) : 1, x, g.cells[r][c]))
end

"The start or end of the line of the screen that the caret is on"
screen_edge(e, by::Int) = begin
  cell = cellat(e.buf, e.buf.caret)
  cell === nothing || return (e.buf.caret[1], by < 0 ? cell.lo : cell.hi)
  i, col = e.buf.caret
  f = flow(e, i)
  k, _ = spot(f, col)
  vl = f.lines[k]
  by < 0 ? (i, vl.from) : (i, k < length(f.lines) ? max(vl.from, vl.to - 1) : vl.to)
end

"Move the caret to `p`, which was reached by going in the direction `by`. With `extend`, the selection grows to it."
move!(e, p::Pos, extend::Bool; keep_goal=false, by=0) = begin
  p = settle(e.buf, p, by)
  e.buf.caret = p
  extend || (e.buf.anchor = p)
  touch!(e; keep_goal)
end

erase!(e, to::Pos) = begin
  b = e.buf
  cell = cellat(b, b.caret)
  # In a table, a cell's edges can't be deleted
  cell === nothing || selecting(b) || (to[1] == b.caret[1] && within(cell, to[2])) || return
  selecting(b) || (b.anchor = to)
  type!(e, "")
end

"Return starts a new line. In a list or a quote, the new line carries it on."
newline!(e) = begin
  b = e.buf
  i, col = b.caret
  text, line = b.lines[i], kinds(b)[i]
  k = line.kind
  isempty(rowcells(b, b.caret)) || return next_cell!(e, false, down=true)
  if selecting(b) || col < line.prefix || !(k in (Kind.bullet, Kind.ordered, Kind.blockquote, Kind.paragraph))
    return type!(e, "\n")
  end
  lead = head(text, line.prefix)
  # Return on an empty list item ends the list
  if length(text) == line.prefix && k != Kind.paragraph
    b.anchor = (i, 0)
    return type!(e, "")
  end
  m = k == Kind.ordered ? match(r"^(\s*)(\d+)(.*)$", lead) : nothing
  m === nothing || (lead = string(m[1], parse(Int, m[2]) + 1, m[3]))
  type!(e, "\n" * lead)
end

"Tab moves a list item in, and shift-Tab moves it back out"
indent!(e, out::Bool) = begin
  b = e.buf
  i, col = b.caret
  k = kinds(b)[i].kind
  isempty(rowcells(b, b.caret)) || return next_cell!(e, out)
  k in (Kind.bullet, Kind.ordered) && !selecting(b) || return out ? nothing : type!(e, "  ")
  n = out ? min(2, kinds(b)[i].level) : 2
  edit!(b, (i, 0), (i, out ? n : 0), out ? "" : "  ")
  b.caret = b.anchor = (i, max(0, col + (out ? -n : n)))
  touch!(e)
end

"""
Go to the next cell of a table and select what's in it, or with `back` the one
before. With `down`, go to the same cell of the next row. Going on from the end
of the table adds a row.
"""
next_cell!(e, back::Bool; down=false) = begin
  b = e.buf
  i, col = b.caret
  s, t = table(b, i)
  rows = tablerows((s, t))
  r = findfirst(==(i), rows)
  cs = tablecells(b.lines[i])
  c = nearest(cs, col)
  if down
    r += 1
  elseif back
    c -= 1
    c < 1 && (r -= 1; c = 0)
  else
    c += 1
    c > length(cs) && (r += 1; c = 1)
  end
  r < 1 && return
  if r > length(rows)
    edit!(b, line_end(b, t), line_end(b, t), "\n|" * repeat("  |", length(tablecells(b.lines[s]))))
    push!(rows, t + 1)
  end
  cs = tablecells(b.lines[rows[r]])
  isempty(cs) && return move!(e, (rows[r], 0), false)
  cell = cs[c == 0 ? length(cs) : min(c, length(cs))]
  b.anchor, b.caret = (rows[r], cell.lo), (rows[r], cell.hi)
  touch!(e)
end

"Put `mark` around the selection, or take it away if it's there already"
surround!(e, mark::String) = begin
  b = e.buf
  lo, hi = selection(b)
  lo[1] == hi[1] || return
  i, n = lo[1], length(mark)
  line = b.lines[i]
  inner = rest(head(line, hi[2]), lo[2])
  if lo[2] >= n && rest(head(line, lo[2]), lo[2] - n) == mark && head(rest(line, hi[2]), n) == mark
    edit!(b, (i, lo[2] - n), (i, hi[2] + n), inner)
    b.anchor, b.caret = (i, lo[2] - n), (i, hi[2] - n)
  else
    edit!(b, lo, hi, mark * inner * mark)
    b.anchor, b.caret = (i, lo[2] + n), (i, hi[2] + n)
  end
  touch!(e)
end

copy_selection!(e) = selecting(e.buf) && clipboard(excerpt(e.buf, selection(e.buf)...))
paste!(e) = type!(e, replace(clipboard(), "\r\n" => "\n", '\r' => '\n', '\t' => "  "))

zoom!(e, z) = (e.zoom = clamp(z, 0.6, 2.5); restyle!(e))

const THEME_ORDER = (:sepia, :paper, :night)
next_theme!(e) = (e.theme = THEME_ORDER[mod1(findfirst(==(e.theme), THEME_ORDER) + 1, 3)]; restyle!(e))

const STATS = (:words, :chars, :minutes)
next_stat!(e) = (e.stat = STATS[mod1(findfirst(==(e.stat), STATS) + 1, 3)])

ismouse(k) = k in (Keys.mouse_left, Keys.mouse_right, Keys.mouse_middle)

onkey(e::Editor, ev::KeyPress{K}) where K = begin
  ismouse(K) && return
  w = ev.window
  shift, cmd, opt, ctrl = Keys.shft in w.keys, Keys.cmd in w.keys, Keys.opt in w.keys, Keys.ctrl in w.keys
  b = e.buf
  e.popup == :finder && return finder_key!(e, K)
  if K == Keys.escape
    e.popup = :none
    b.anchor = b.caret
  elseif cmd && opt && K == Keys.i
    toggle_inspector!(w)
  elseif cmd && K == Keys.s
    save!(b)
  elseif cmd && K == Keys.z
    shift ? redo!(b) : undo!(b)
    touch!(e)
  elseif cmd && K == Keys.a
    b.anchor, b.caret = (1, 0), line_end(b, length(b.lines))
  elseif cmd && K == Keys.c
    copy_selection!(e)
  elseif cmd && K == Keys.x
    copy_selection!(e) === false || type!(e, "")
  elseif cmd && K == Keys.v
    paste!(e)
  elseif cmd && K == Keys.b
    surround!(e, "**")
  elseif cmd && K == Keys.i
    surround!(e, "*")
  elseif cmd && K == Keys.p
    open_finder!(e)
  elseif cmd && K == Keys.backslash
    e.panel = !e.panel
  elseif cmd && K == Keys.equal
    zoom!(e, e.zoom + 0.1)
  elseif cmd && K == Keys.minus
    zoom!(e, e.zoom - 0.1)
  elseif cmd && K == getproperty(Keys, Symbol(0))
    zoom!(e, 1.0)
  elseif K == Keys.left || K == Keys.right
    by = K == Keys.left ? -1 : 1
    lo, hi = selection(b)
    to = cmd ? screen_edge(e, by) : opt ? word_step(b, b.caret, by) :
         selecting(b) && !shift ? (by < 0 ? lo : hi) : beside(b, b.caret, by)
    move!(e, to, shift; by)
  elseif K == Keys.up || K == Keys.down
    by = K == Keys.up ? -1 : 1
    to = cmd ? (by < 0 ? (1, 0) : line_end(b, length(b.lines))) : vertical(e, by)
    move!(e, to, shift; keep_goal=!cmd, by)
  elseif K == Keys.pageup || K == Keys.pagedown
    for _ in 1:20
      by = K == Keys.pageup ? -1 : 1
      move!(e, vertical(e, by), shift; keep_goal=true, by)
    end
  elseif K == Keys.home || K == Keys._end
    move!(e, screen_edge(e, K == Keys.home ? -1 : 1), shift)
  elseif K == Keys.backspace
    erase!(e, cmd ? (b.caret[1], 0) : opt ? word_step(b, b.caret, -1) : beside(b, b.caret, -1))
  elseif K == Keys.delete
    erase!(e, opt ? word_step(b, b.caret, 1) : beside(b, b.caret, 1))
  elseif K == Keys.enter
    newline!(e)
  elseif K == Keys.tab
    indent!(e, shift)
  elseif !cmd && !ctrl && !opt && haskey(TYPED, K)
    type!(e, string(TYPED[K][shift ? 2 : 1]), typing=true)
  end
  nothing
end

# --- the top bar ------------------------------------------------------------------------

describe(b::ToolButton) = begin
  e = editor(b)
  on = (b.action == :panel && e.panel) || (b.action == :outline && e.popup == :outline)
  Box(width(30px), height(28px), radius(6px), Alignment.Center, name="Button",
      background(on ? colours.active : ishovered(b) ? colours.hover : clear),
    Icon(b.icon, size=15px, color=colours.dim))
end

onkey(b::ToolButton, ::KeyPress{Keys.mouse_left}) = begin
  e = editor(b)
  a = b.action
  a == :panel ? (e.panel = !e.panel) :
  a == :outline ? (e.popup = e.popup == :outline ? :none : :outline) :
  a == :font ? (e.serif = !e.serif; restyle!(e)) :
  a == :theme ? next_theme!(e) : nothing
  focus(e)
end

commas(n::Int) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

describe(c::Count) = begin
  e = editor(c)
  b = e.buf
  kinds(b)
  s = e.stat == :words ? "$(commas(b.words)) $(b.words == 1 ? "word" : "words")" :
      e.stat == :chars ? "$(commas(b.chars)) characters" : "$(max(1, round(Int, b.words / 230))) min read"
  Box(height(28px), padding(8px, 0px), radius(6px), background(ishovered(c) ? colours.hover : clear),
    label(s, 12px, color=colours.dim))
end

onkey(c::Count, ::KeyPress{Keys.mouse_left}) = next_stat!(editor(c))

button(e, action, icon) = node!(() -> ToolButton(icon=icon, action=action), e, action)

describe(t::TopBar) = begin
  e = editor(t)
  b = e.buf
  side = 250px
  Row(width(grow=grow), height(TOPBAR_H), name="TopBar",
    # The close, minimise and zoom buttons sit over the first 78px
    Row(fixed(side), height(grow=grow), padding(0px, 0px, 0px, 78px), button(e, :panel, "layout-sidebar")),
    Box(width(grow=grow), height(grow=grow), clip=true,
      Row(child_gap=6px,
        label(name(b), 13px, color=colours.dim),
        (dirty(b) ? (label("— edited", 13px, color=colours.faint),) : ())...)),
    Row(fixed(side), height(grow=grow), justify=Alignment.End, padding(0px, 10px, 0px, 0px), child_gap=2px,
      node!(Count, e, :count),
      button(e, :outline, "list-nested"),
      button(e, :font, "fonts"),
      button(e, :theme, "circle-half")))
end

# The window has no title bar, so you move it by dragging the top bar
onkey(t::TopBar, ::KeyPress{Keys.mouse_left}) = drag_window!(window_of(t))

# --- the file panel -----------------------------------------------------------------------

title(path) = splitext(basename(path))[1]

describe(r::FileRow) = begin
  e = editor(r)
  open = r.finder == 0 ? r.path == e.buf.path : r.finder == e.picked
  changed = haskey(e.buffers, r.path) && dirty(e.buffers[r.path])
  Row(width(grow=grow), height(28px), padding(10px, 0px), radius(6px), child_gap=8px, clip=true, name="File",
      background(open ? colours.active : ishovered(r) ? colours.hover : clear),
    Icon("file-earmark-text", size=13px, color=colours.dim),
    Box(width(grow=grow), Alignment.Start, label(title(r.path), weight=open ? "Semibold" : "")),
    (changed ? (Box(width(6px), height(6px), radius(3px), background(colours.dim)),) : ())...)
end

onkey(r::FileRow, ::KeyPress{Keys.mouse_left}) = open!(editor(r), r.path)

panel(e) =
  Column(fixed(PANEL_W), height(grow=grow), Alignment.Start, background(colours.panel), name="Files",
         border(1px, :solid, colours.line)[:right],
    Row(width(grow=grow), height(30px), padding(16px, 0px), clip=true,
      label(uppercase(basename(e.folder)), 11px, color=colours.dim, weight="Semibold")),
    reuse!(e.files_scroll,
      Column(width(grow=grow), Alignment.Start, padding(0px, 8px, 12px, 8px), child_gap=1px,
        [node!(() -> FileRow(path=p), e, (:file, p)) for p in e.files]...)))

# --- the outline ----------------------------------------------------------------------------

"The headings of the document, as (line, level, title)"
headings(b::Buffer) =
  [(i, l.level, rest(b.lines[i], l.prefix)) for (i, l) in enumerate(kinds(b)) if l.kind == Kind.heading]

describe(r::OutlineRow) =
  Row(width(grow=grow), height(26px), padding(0px, 10px, 0px, 10px + 14px * (r.level - 1)), radius(5px), clip=true,
      background(ishovered(r) ? colours.hover : clear),
    label(r.title, color=r.level == 1 ? colours.ink : colours.dim, weight=r.level == 1 ? "Semibold" : ""))

onkey(r::OutlineRow, ::KeyPress{Keys.mouse_left}) = begin
  e = editor(r)
  e.popup = :none
  e.buf.caret = e.buf.anchor = (r.line, length(e.buf.lines[r.line]))
  focus(e)
  # Put the heading near the top of the window rather than just on screen
  e.scroll.offset = max(0px, PAGE_TOP + item(e, r.line).top - 24px)
  e.blink = time()
end

floating(children...; w) =
  Column(fixed(w), radius(9px), Alignment.Start, background(colours.float), border(1px, :solid, colours.line), children...)

outline(e) = begin
  hs = headings(e.buf)
  _, h = window_size(e)
  found = [node!(() -> OutlineRow(line=i, level=l, title=t), e, (:heading, i, l, t)) for (i, l, t) in hs]
  high = min(26px * max(1, length(found)) + 12px, h - TOPBAR_H - 40px)
  list = isempty(found) ?
    Box(width(grow=grow), height(grow=grow), label("No headings yet", color=colours.dim)) :
    reuse!(e.outline_scroll, Column(width(grow=grow), Alignment.Start, padding(6px), found...))
  Row(width(grow=grow), height(grow=grow), Alignment.Start, justify=Alignment.End, padding(TOPBAR_H - 4px, 12px, 0px, 0px),
    floating(Box(width(grow=grow), height(high), list), w=300px))
end

# The backdrop only dims the window behind the file finder
describe(b::Backdrop) = Box(width(grow=grow), height(grow=grow), background(editor(b).popup == :finder ? colours.shade : clear))
onkey(b::Backdrop, ::KeyPress) = (e = editor(b); e.popup = :none; focus(e))

# --- the file finder -----------------------------------------------------------------------

open_finder!(e) = begin
  e.popup = :finder
  e.picked = 1
  i = input(e)
  i.text = ""
  i.cursor = i.anchor = 0
  list_files!(e)
  focus(i)
end

"The files whose names have the letters typed, in order"
matches(e) = begin
  q = lowercase(input(e).text)
  filter(e.files) do path
    name = lowercase(title(path))
    at = firstindex(name)
    all(q) do c
      found = findnext(c, name, at)
      found === nothing ? false : (at = nextind(name, found); true)
    end
  end
end

finder_key!(e, K) = begin
  found = matches(e)
  if K == Keys.escape
    e.popup = :none
    focus(e)
  elseif K == Keys.enter
    isempty(found) ? (e.popup = :none; focus(e)) : open!(e, found[clamp(e.picked, 1, length(found))])
  elseif K == Keys.down
    e.picked = min(e.picked + 1, max(1, length(found)))
  elseif K == Keys.up
    e.picked = max(e.picked - 1, 1)
  else
    e.picked = 1
  end
  nothing
end

describe(f::FinderInput) = begin
  e = editor(f)
  Row(width(grow=grow), height(44px), padding(14px, 0px), child_gap=10px,
    Icon("search", size=14px, color=colours.dim), input(e))
end
onkey(f::FinderInput, ::KeyPress{Keys.mouse_left}) = focus(input(editor(f)))
cursor(::FinderInput) = :ibeam

finder(e) = begin
  i = input(e)
  i.color, i.placeholder_color = colours.ink, colours.faint
  found = first(matches(e), 9)
  picks = [node!(() -> FileRow(path=p, finder=n), e, (:pick, n, p)) for (n, p) in enumerate(found)]
  list = isempty(picks) ?
    Box(width(grow=grow), height(40px), label("No file has that name", color=colours.dim)) :
    Column(width(grow=grow), Alignment.Start, padding(6px), child_gap=1px, picks...)
  Row(width(grow=grow), height(grow=grow), Alignment.Start, justify=Alignment.Center, padding(90px, 0px, 0px, 0px),
    floating(node!(FinderInput, e, :finder_input),
             Box(width(grow=grow), height(1px), background(colours.line)),
             list, w=460px))
end

# --- the whole window ---------------------------------------------------------------------

describe(e::Editor) = begin
  use!(getproperty(THEMES, e.theme))
  win = window_of(e)
  if win !== nothing && e.applied != e.theme
    set_dark!(win, e.theme == :night)
    e.applied = e.theme
  end
  layout!(e)
  e.reveal && (reveal!(e); e.reveal = false)
  # The window is drawn again as soon as a key or the mouse does something, so
  # typing shows without waiting for a frame that was already under way. Between
  # times it only wakes to blink the caret.
  if win !== nothing
    win.animating = false
    win.wake = win.focus === e ? 0.51 - mod(time() - e.blink, 0.5) : win.focus === input(e) ? 0.25 : 0.0
  end
  window = Column(width(grow=grow), height(grow=grow), Alignment.Start, background(colours.bg), name="Editor",
    node!(TopBar, e, :topbar),
    Row(width(grow=grow), height(grow=grow), Alignment.Start,
      (e.panel ? (panel(e),) : ())...,
      node!(Page, e, :page)))
  e.popup == :none && return window
  Stack(width(grow=grow), height(grow=grow), Alignment.Start, name="Editor",
    window, node!(Backdrop, e, :backdrop), e.popup == :outline ? outline(e) : finder(e))
end

# --- window -------------------------------------------------------------------------------

const WELCOME = joinpath(@__DIR__, "markdown_editor", "welcome.md")

"""
Open an editor window and run it until it closes. `args` can name a Markdown
file or a folder, and `--paper` or `--night` to choose the colours.
"""
open_editor(args) = begin
  # macOS can pass its own -options to an app it opens, so skip anything with a dash
  paths = filter(a -> !startswith(a, "-"), args)
  e = build_editor(isempty(paths) ? WELCOME : paths[1])
  e.theme = "--night" in args ? :night : "--paper" in args ? :paper : :sepia
  window = Window(e, title="UI.jl Markdown editor", size=(1100px, 800px))
  focus(e)
  display(window)
end

onopen(::Editor, w::Window) = hide_titlebar!(w)

if abspath(PROGRAM_FILE) == @__FILE__
  open_editor(ARGS)
end
