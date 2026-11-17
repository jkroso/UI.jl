# What a diagram is made of once it's laid out: boxes, lines and words, each
# with its place. A file like flowchart.jl reads the code of one kind of
# diagram and makes a `Picture` of it. main.jl draws the picture.
#
# Every length is a number of px. A colour is a role, like :text or :node,
# which the theme gives a colour when the picture is drawn, so one picture
# suits a light page and a dark one. A colour that the diagram's code asks for
# by name is a colour itself.

@use "github.com/jkroso/Font.jl/units" px
@use "../../fonts" skia_font
@use "../../Specific" text_width
@use Colors: Colorant, RGBA

const Point = NTuple{2,Float64}

"A box, or another closed shape, with its left, its top, its width and its height"
struct Shape
  kind::Symbol     # :rect, :round, :stadium, :diamond, :circle, :hexagon, :cylinder and so on. See `outline` in main.jl.
  x::Float64
  y::Float64
  w::Float64
  h::Float64
  fill::Any        # nothing leaves it empty
  line::Any        # nothing gives it no edge
  thick::Float64   # how thick its edge is
  dash::Symbol     # :solid, :dashed or :dotted
end
Shape(kind, x, y, w, h; fill=:node, line=:edge, thick=1.0, dash=:solid) = Shape(kind, x, y, w, h, fill, line, thick, dash)

"""
A line through `points`. A `curved` line goes from its first point to its
fourth as a curve that the second and third pull towards them, then on to its
seventh and so on. `from` and `to` say what each end has: :none, :arrow, :open,
:circle, :cross, :triangle, :diamond or :hollow, which is an empty diamond.
`around` holds the boxes that the line stops at and starts again after: its labels.
"""
struct Stroke
  points::Vector{Point}
  curved::Bool
  colour::Any
  thick::Float64
  dash::Symbol
  from::Symbol
  to::Symbol
  tip::Float64     # how long an arrow at one of its ends is
  around::Vector{NTuple{4,Float64}}
end
Stroke(points; curved=false, colour=:link, thick=1.2, dash=:solid, from=:none, to=:none, tip=10.0, around=NTuple{4,Float64}[]) =
  Stroke(points, curved, colour, thick, dash, from, to, tip, around)

"One line of text. `x` is its middle, its left or its right, as `align` says, and `y` is its middle."
struct Words
  text::String
  x::Float64
  y::Float64
  align::Symbol    # :middle, :left or :right
  size::Float64
  bold::Bool
  italic::Bool
  colour::Any
end

"A slice of a pie. Angles are in radians, clockwise from 12 o'clock."
struct Slice
  x::Float64
  y::Float64
  r::Float64
  from::Float64
  to::Float64
  fill::Any
end

"""
A part of a diagram that you can select and change: a box, a line, a slice.
`kind` says what it is and `key` says which one, as the file of its kind of
diagram names them. `box` is its left, its top, its width and its height. A
line has a `path` too: the places that it goes through, with a straight piece
between each two. `shape` is the outline that it glows in while it's selected:
the name of a shape, or :area for the shape that has its corners at `path`.
`words` is the middle of the place where its words are typed, and `room` is
how wide and how tall the words that it shows there are. Two parts can have
one kind and key, like the two boxes of someone in a sequence diagram. The
first of them is the one that glows.
"""
struct Part
  kind::Symbol
  key::Any
  box::NTuple{4,Float64}
  path::Vector{Point}
  shape::Symbol
  words::Point
  room::NTuple{2,Float64}
end
Part(kind, key, box; path=Point[], shape=:rect, words=(box[1] + box[3] / 2, box[2] + box[4] / 2), room=(0.0, 0.0)) =
  Part(kind, key, Float64.(box), path, shape, Float64.(words), Float64.(room))

"A part for the label `l`, which has its middle at (x, y): the part's words are the label's"
labelled(kind, key, box, l, x, y; kwargs...) = Part(kind, key, box; words=(x, y), room=(l.w, l.h), kwargs...)

"""
The places that a curved line through `points` goes through, near enough that
straight pieces between them look like the curve. See `Stroke`.
"""
flat(points::Vector{Point}; steps=10) = begin
  length(points) < 4 && return copy(points)
  out = Point[points[1]]
  for i in 2:3:length(points)-2
    a, b, c, d = points[i-1], points[i], points[i+1], points[i+2]
    for k in 1:steps
      t = k / steps
      s = 1 - t
      push!(out, (s^3 * a[1] + 3s^2 * t * b[1] + 3s * t^2 * c[1] + t^3 * d[1], s^3 * a[2] + 3s^2 * t * b[2] + 3s * t^2 * c[2] + t^3 * d[2]))
    end
  end
  out
end

"The middle of a line through `path`: the place that's half of its length along it"
halfway(path::Vector{Point}) = begin
  isempty(path) && return (0.0, 0.0)
  lengths = [hypot(path[i+1][1] - path[i][1], path[i+1][2] - path[i][2]) for i in 1:length(path)-1]
  left = sum(lengths; init=0.0) / 2
  for (i, l) in enumerate(lengths)
    left <= l && l > 0 && return (path[i][1] + (path[i+1][1] - path[i][1]) * left / l, path[i][2] + (path[i+1][2] - path[i][2]) * left / l)
    left -= l
  end
  path[end]
end

"""
Something that you can do to a diagram, or to the part of it that's selected.
`icon` is the name of the icon of its button, and `tip` says what it does. A
tool with `choices` asks which: each is what a choice says and what it gives
the tool. A tool with `target` needs a second part, which you click next.
"""
struct Tool
  name::Symbol
  icon::String
  tip::String
  choices::Vector{Pair{String,Any}}
  target::Bool
end
Tool(name, icon, tip; choices=Pair{String,Any}[], target=false) = Tool(name, icon, tip, collect(Pair{String,Any}, choices), target)

"A diagram that's laid out: how wide and how tall it is, what it's made of, from the back to the front, and the parts of it that can be selected"
struct Picture
  w::Float64
  h::Float64
  items::Vector{Any}
  parts::Vector{Part}
end
Picture(w, h, items) = Picture(w, h, items, Part[])

"What went wrong with the code of a diagram, and the line of the code that it's on"
struct Problem <: Exception
  line::Int
  message::String
end
Base.showerror(io::IO, p::Problem) = print(io, p.line > 0 ? "Line $(p.line): " : "", p.message)

"The font that a diagram's words are in, and how big they are in px. A layout measures its words with it."
struct Pen
  family::String
  size::Float64
end

font(p::Pen; size=p.size, bold=false, italic=false) =
  skia_font(p.family, px(size), bold ? (italic ? "Bold Italic" : "Bold") : italic ? "Italic" : "")

"How wide `text` is"
wide(p::Pen, text::AbstractString; kwargs...) = isempty(text) ? 0.0 : Float64(text_width(font(p; kwargs...), text).value)

"How far a line of text is from the next one"
leading(p::Pen, size=p.size) = 1.35size

"Some lines of text, and how wide and how tall they are together"
struct Label
  lines::Vector{String}
  w::Float64
  h::Float64
  size::Float64
  bold::Bool
  italic::Bool
end

"""
`text` as lines that are no wider than `most`. A line of the text stays a line,
and a line that's too wide breaks between two of its words.
"""
label(p::Pen, text::AbstractString; most=Inf, size=p.size, bold=false, italic=false) = begin
  lines = String[]
  for line in split(text, '\n')
    line = strip(line)
    if wide(p, line; size, bold, italic) <= most
      push!(lines, line)
      continue
    end
    now = ""
    for word in split(line)
      longer = isempty(now) ? String(word) : now * " " * word
      if isempty(now) || wide(p, longer; size, bold, italic) <= most
        now = longer
      else
        push!(lines, now)
        now = String(word)
      end
    end
    isempty(now) || push!(lines, now)
  end
  all(isempty, lines) && return Label(String[], 0.0, 0.0, size, bold, italic)
  Label(lines, maximum(l -> wide(p, l; size, bold, italic), lines), leading(p, size) * length(lines), size, bold, italic)
end

"Put the lines of `l` in the picture, with the middle of the label at (`x`, `y`)"
write!(items, l::Label, x, y; colour=:text, align=:middle) = begin
  step = isempty(l.lines) ? 0.0 : l.h / length(l.lines)
  # A line that isn't in the middle starts at the label's left, or ends at its right
  at = align == :left ? x - l.w / 2 : align == :right ? x + l.w / 2 : x
  for (i, line) in enumerate(l.lines)
    isempty(line) || push!(items, Words(line, at, y - l.h / 2 + step * (i - 0.5), align, l.size, l.bold, l.italic, colour))
  end
  items
end

"Put the lines of `l` in the picture, with the label's left side at `left` and its middle `y` down"
write_from!(items, l::Label, left, y; colour=:text) = write!(items, l, left + l.w / 2, y; colour, align=:left)

"""
The text of a label as the diagram's code gives it, made plain. The code can
have the text in quotes, with `<br>` for a new line and with a name for a
character that would mean something else, like `#quot;`.
"""
plain(text::AbstractString) = begin
  s = strip(text)
  # Text in "`…`" is Markdown. Its ** and * come off, because a label is in one weight.
  if length(s) >= 2 && startswith(s, '"') && endswith(s, '"')
    s = strip(chop(s, head=1, tail=1))
    if length(s) >= 2 && startswith(s, '`') && endswith(s, '`')
      s = replace(chop(s, head=1, tail=1), r"\*\*|__" => "", r"(?<![\w*])\*|\*(?![\w*])" => "")
    end
  end
  s = replace(s, r"<br\s*/?>"i => "\n", "\\n" => "\n")
  s = replace(s, r"</?[a-zA-Z][^<>]*>" => "")      # any other tag of HTML
  s = replace(s, r"\bfa[bsrl]?:fa-[\w-]+\s*" => "")  # the name of an icon, which isn't drawn
  s = replace(s, r"#(\d+);" => m -> string(Char(parse(Int, m[2:end-1]))))
  s = replace(s, "#quot;" => "\"", "#amp;" => "&", "#lt;" => "<", "#gt;" => ">", "#nbsp;" => " ", "&nbsp;" => " ",
              "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"")
  String(strip(s))
end

"The colour that the code of a diagram names, like `#f9f` or `tomato`, or nothing if it isn't the name of a colour"
paint(name::AbstractString) = begin
  name = strip(name)
  lowercase(name) in ("none", "transparent", "") && return nothing
  try
    parse(Colorant, name)
  catch
    nothing
  end
end

"""
What a list of styles says, like `fill:#f9f,stroke:#333,stroke-width:2px`: each name with what it's set to
"""
styles(text::AbstractString) = begin
  out = Dict{String,String}()
  # A comma can be in a colour, like rgb(1,2,3), so a new style starts at a comma that a name and a colon follow
  for part in split(text, r",(?=\s*[\w-]+\s*:)")
    m = match(r"^\s*([\w-]+)\s*:\s*(.*?)\s*;?\s*$", part)
    m === nothing || (out[lowercase(m[1])] = String(m[2]))
  end
  out
end

"Black or white, whichever shows on `fill`"
on(fill) = begin
  c = convert(RGBA{Float64}, fill)
  0.299c.r + 0.587c.g + 0.114c.b > 0.6 ? RGBA(0.1, 0.1, 0.1, 1.0) : RGBA(1.0, 1.0, 1.0, 1.0)
end

"The fill, the edge, the thickness of the edge, its dashes and the colour of the text that `style` gives, with the usual ones for the rest"
look(style, u; fill=:node, line=:edge, thick=0.08u) = begin
  text = :text
  if haskey(style, "fill")
    fill = paint(style["fill"])
    fill === nothing || (text = on(fill))
  end
  haskey(style, "stroke") && (line = paint(style["stroke"]))
  if haskey(style, "stroke-width")
    n = tryparse(Float64, replace(style["stroke-width"], r"[a-z%\s]" => ""))
    n === nothing || (thick = n * u / 16)
  end
  haskey(style, "color") && (text = something(paint(style["color"]), text))
  dash = haskey(style, "stroke-dasharray") && !(strip(style["stroke-dasharray"]) in ("0", "none")) ? :dashed : :solid
  fill, line, thick, dash, text
end

"""
The lines of a diagram's code that say something, each with its number in the
code. A comment, which starts with %%, is left out, and so is what's between
two lines of `---` at the top. Returns the lines and the title that the top gave, if it gave one.
"""
statements(code::AbstractString) = begin
  out = Tuple{Int,String}[]
  title = ""
  lines = split(code, '\n')
  i = 1
  while i <= length(lines) && isempty(strip(lines[i]))
    i += 1
  end
  if i <= length(lines) && strip(lines[i]) == "---"
    close = findnext(l -> strip(l) == "---", lines, i + 1)
    if close !== nothing
      for l in lines[i+1:close-1]
        m = match(r"^\s*title:\s*(.*)$", l)
        m === nothing || (title = plain(m[1]))
      end
      i = close + 1
    end
  end
  for n in i:length(lines)
    line = strip(replace(lines[n], r"%%\{.*?\}%%" => ""))
    (isempty(line) || startswith(line, "%%")) && continue
    push!(out, (n, String(line)))
  end
  out, title
end

# --- changing the code -----------------------------------------------------------
#
# A change to a diagram changes only the lines of its code that say the part
# that changed. The rest stays as it was written: its comments, its styles and
# what isn't drawn here.

"The white space that `line` starts with"
indent(line::AbstractString) = String(match(r"^[ \t]*", line).match)

"""
`code` with other lines in place of some of its lines. `new` gives the lines
that go in place of the line with each number: none takes the line away. Each
new line starts as far in as the old one did.
"""
relined(code::AbstractString, new::AbstractDict) = begin
  out = String[]
  for (n, line) in enumerate(split(code, '\n'))
    haskey(new, n) ? append!(out, (indent(line) * l for l in new[n])) : push!(out, String(line))
  end
  join(out, '\n')
end

"""
`code` with the lines `more` after its last line that says something, or after
the line with the number `after`. They start as far in as the line under the
first one does.
"""
added(code::AbstractString, more::AbstractString...; after=nothing) = begin
  lines = String.(split(code, '\n'))
  said, _ = statements(code)
  isempty(said) && return code
  last = something(after, said[end][1])
  # As far in as the second line that says something, or two spaces in from the first when it's the only one
  pad = length(said) > 1 ? indent(lines[said[2][1]]) : indent(lines[said[1][1]]) * "  "
  join(vcat(lines[1:last], [pad * m for m in more], lines[last+1:end]), '\n')
end

"`code` with what its lines `a` and `b` say in each other's place. Each stays as far in as the line that was there."
swapped(code::AbstractString, a::Int, b::Int) = begin
  lines = split(code, '\n')
  relined(code, Dict(a => [String(strip(lines[b]))], b => [String(strip(lines[a]))]))
end

"The code units `at` of `line`, as text"
cut(line::AbstractString, at::UnitRange{Int}) = String(codeunits(line)[at])

"`line` with `new` in place of its code units `at`"
spliced(line::AbstractString, at::UnitRange{Int}, new::AbstractString) =
  String(codeunits(line)[1:at.start-1]) * new * String(codeunits(line)[at.stop+1:end])

"`line` with `new` in place of its code units `at`, and a space each side of it where the line has none"
spaced(line::AbstractString, at::UnitRange{Int}, new::AbstractString) = begin
  units = codeunits(line)
  gap(i) = 1 <= i <= length(units) && !(units[i] in (UInt8(' '), UInt8('\t'))) ? " " : ""
  spliced(line, at, gap(at.start - 1) * new * gap(at.stop + 1))
end

"The words of a part as you type them: one line, with <br> where they go on to a new line"
typed(text::AbstractString) = replace(text, '\n' => "<br>")

"""
Words that were typed, as the code of a diagram writes them. They're in quotes
when they have a character that means something else to the code, or with
`always`. A " in them is written as #quot;.
"""
quoted(text::AbstractString; always=false, safe=r"^[\p{L}\p{N} .,!?'%+-]*$") = begin
  text = replace(strip(replace(text, '\n' => "<br>")), '"' => "#quot;")
  always || !occursin(safe, text) ? "\"" * text * "\"" : String(text)
end

export Point, Part, Tool, flat, halfway, indent, relined, added, typed, quoted, cut, spliced, spaced, swapped, labelled, Shape, Stroke, Words, Slice, Picture, Problem, Pen, Label, font, wide, leading, label, write!, write_from!, plain, statements, paint, styles, on, look
