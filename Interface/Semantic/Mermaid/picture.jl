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

"A diagram that's laid out: how wide and how tall it is, and what it's made of, from the back to the front"
struct Picture
  w::Float64
  h::Float64
  items::Vector{Any}
end

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

export Point, Shape, Stroke, Words, Slice, Picture, Problem, Pen, Label, font, wide, leading, label, write!, write_from!, plain, statements, paint, styles, on, look
