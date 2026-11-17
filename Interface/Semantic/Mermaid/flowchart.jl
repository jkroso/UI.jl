# A flowchart: boxes with lines between them.
#
#     flowchart TD
#       A[Start] --> B{Is it done?}
#       B -- Yes --> C([Stop])
#       B -- No --> A
#
# The first line says which way it goes: TD or TB for down, BT for up, LR for
# left to right and RL for right to left. What comes after a box's name gives
# its shape and its text: [a box], (a round box), ([a pill]), {a diamond},
# ((a circle)), {{a hexagon}}, [(a drum)], [[a box with bars]], [/a leaning box/]
# and >a flag]. A line is -->, ---, -.-> for dots or ==> for a thick one, and
# its text goes in the middle of it or after it as |text|. `subgraph` to `end`
# puts a box around the boxes between them. `style` and `classDef` give a box
# its own colours.

@use "./picture"...
@use "./graph" Box Link arrange! across

mutable struct Node
  id::String
  text::String
  shape::Symbol
  classes::Vector{String}
  style::Dict{String,String}
  group::Int   # the subgraph that it's in, or 0
end

mutable struct Group
  id::String
  title::String
  inside::Int
  dir::Union{Symbol,Nothing}
  classes::Vector{String}
  style::Dict{String,String}
  opens::Int    # the line of the code that it opens on
  closes::Int   # the line with its `end`, or 0 while it's open
end

mutable struct Edge
  from::String
  to::String
  text::String
  kind::Symbol   # :solid, :thick, :dotted or :hidden
  tail::Symbol   # what its ends have: :none, :arrow, :circle or :cross
  head::Symbol
  len::Int
  style::Dict{String,String}
end

"A box where the code names it. `at` is where that is in its line, and `look` is where its shape and its text are, after its name: nowhere when it has none."
struct Named
  id::String
  text::Union{String,Nothing}
  classes::Vector{String}
  at::UnitRange{Int}
  look::UnitRange{Int}
end

"A line between boxes where the code draws it, with where that is in its line of code"
struct Linked
  edge::Edge
  at::UnitRange{Int}
end

"""
Boxes with lines between them, as one line of the code writes them: A & B --> C --> D.
`n` is the line's number in the code and `line` is what it says. Each group
holds the boxes that an & is between, and a line of the chart goes from each
box of a group to each box of the next. `first` is the number that the first
of those lines has among the lines of the chart.
"""
struct Chain
  n::Int
  line::String
  groups::Vector{Vector{Named}}
  links::Vector{Linked}
  first::Int
end

mutable struct Chart
  dir::Symbol
  nodes::Vector{Node}
  named::Dict{String,Int}
  groups::Vector{Group}
  edges::Vector{Edge}
  classes::Dict{String,Dict{String,String}}
  links::Dict{String,String}   # the style for every line
  chains::Vector{Chain}        # where the code names each box and draws each line
end

const DIRS = Dict("TB" => :TB, "TD" => :TB, "BT" => :BT, "LR" => :LR, "RL" => :RL)

"The parts of `line` that a ; is between. A ; in quotes or in brackets is part of a label."
pieces(line) = begin
  out, depth, quoted, from = SubString{String}[], 0, false, firstindex(line)
  for (i, c) in pairs(line)
    if c == '"'
      quoted = !quoted
    elseif !quoted && c in "[({"
      depth += 1
    elseif !quoted && c in "])}"
      depth = max(0, depth - 1)
    elseif !quoted && depth == 0 && c == ';'
      push!(out, strip(SubString(line, from, prevind(line, i))))
      from = nextind(line, i)
    end
  end
  push!(out, strip(SubString(line, from)))
  filter(!isempty, out)
end

# What opens each shape, what closes it and the shape. The longest come first, so that (( isn't read as (.
const SHAPES = [("(((", ")))", :double_circle), ("((", "))", :circle), ("([", "])", :stadium), ("[[", "]]", :subroutine),
                ("[(", ")]", :cylinder), ("[/", "/]", :lean_right), ("[/", "\\]", :trapezoid), ("[\\", "\\]", :lean_left),
                ("[\\", "/]", :trapezoid_alt), ("{{", "}}", :hexagon), ("(", ")", :round), ("[", "]", :rect),
                ("{", "}", :diamond), (">", "]", :flag)]

# The names that the newer form, A@{ shape: … }, has for the shapes that are drawn here
const NAMED_SHAPES = Dict("rect" => :rect, "rectangle" => :rect, "process" => :rect, "rounded" => :round, "event" => :round,
  "stadium" => :stadium, "pill" => :stadium, "terminal" => :stadium, "diam" => :diamond, "diamond" => :diamond,
  "decision" => :diamond, "question" => :diamond, "circle" => :circle, "circ" => :circle, "dbl-circ" => :double_circle,
  "double-circle" => :double_circle, "hex" => :hexagon, "hexagon" => :hexagon, "prepare" => :hexagon, "cyl" => :cylinder,
  "cylinder" => :cylinder, "database" => :cylinder, "db" => :cylinder, "subproc" => :subroutine, "subroutine" => :subroutine,
  "fr-rect" => :subroutine, "lean-r" => :lean_right, "lean-right" => :lean_right, "in-out" => :lean_right,
  "lean-l" => :lean_left, "lean-left" => :lean_left, "out-in" => :lean_left, "trap-b" => :trapezoid, "trapezoid" => :trapezoid,
  "priority" => :trapezoid, "trap-t" => :trapezoid_alt, "inv-trapezoid" => :trapezoid_alt, "manual" => :trapezoid_alt,
  "odd" => :flag, "sm-circ" => :circle, "start" => :circle, "text" => :rect)

const ID = r"^[\p{L}\p{N}_]+(?:[-.][\p{L}\p{N}_]+)*"

"""
Read a box from the start of `s`: its name, then its shape and text if it has
them, then its classes. Returns the name, the shape or nothing, the text or
nothing, the classes, what's left of `s`, and how many code units its shape
and text take after its name.
"""
read_node(s, line) = begin
  m = match(ID, s)
  m === nothing && throw(Problem(line, "A box's name was expected at \"$(first(s, 20))\""))
  id, rest = String(m.match), SubString(s, ncodeunits(m.match) + 1)
  named = ncodeunits(rest)
  shape, text = nothing, nothing
  if startswith(rest, "@{")
    close = findfirst('}', rest)
    close === nothing && throw(Problem(line, "The { after $id is never closed"))
    inner = rest[3:prevind(rest, close)]
    named = match(r"shape:\s*([\w-]+)", inner)
    named === nothing || (shape = get(NAMED_SHAPES, lowercase(named[1]), :rect))
    said = match(r"label:\s*(\"[^\"]*\"|[^,}]+)", inner)
    said === nothing || (text = plain(said[1]))
    rest = SubString(rest, nextind(rest, close))
  else
    for (open, _, _) in SHAPES
      startswith(rest, open) || continue
      inner = SubString(rest, ncodeunits(open) + 1)
      closers = [(c, kind) for (o, c, kind) in SHAPES if o == open]
      # Text in quotes can have a bracket in it, so the shape closes after the quotes
      skip = 0
      quoted = match(r"^\s*\"[^\"]*\"\s*", inner)
      quoted === nothing || (skip = ncodeunits(quoted.match))
      found = [(findnext(c, inner, skip + 1), c, kind) for (c, kind) in closers]
      found = [(first(r), c, kind) for (r, c, kind) in found if r !== nothing]
      isempty(found) && throw(Problem(line, "The $open after $id is never closed"))
      at, closer, shape = argmin(first, found)
      text = plain(inner[1:prevind(inner, at)])
      rest = SubString(inner, at + ncodeunits(closer))
      break
    end
  end
  look = named - ncodeunits(rest)
  classes = String[]
  while (c = match(r"^:::([\w-]+)", rest)) !== nothing
    push!(classes, c[1])
    rest = SubString(rest, ncodeunits(c.match) + 1)
  end
  id, shape, text, classes, rest, look
end

const WHOLE_LINK = r"^(<|[xo](?=[-=]))?(?:(-{2,})|(={2,})|-(\.+)-|(~{3,}))(>|[xo](?=\s|\||$))?"
const OPEN_LINK = [(r"^(<|[xo](?=-))?--(?![->])\s*(.+?)\s*(-{2,})(>|[xo](?=\s|\||$))?", :solid),
                   (r"^(<|[xo](?==))?==(?![=>])\s*(.+?)\s*(={2,})(>|[xo](?=\s|\||$))?", :thick),
                   (r"^(<|[xo](?=-))?-\.(?![.-])\s*(.+?)\s*(\.+)-(>|[xo](?=\s|\||$))?", :dotted)]

end_of(mark) = mark === nothing ? :none : mark in ("<", ">") ? :arrow : mark == "o" ? :circle : :cross

"Read a line between two boxes from the start of `s`. Returns an Edge with no ends yet and what's left of `s`, or nothing."
read_link(s) = begin
  edge, rest = nothing, s
  m = match(WHOLE_LINK, s)
  if m !== nothing
    kind, n = m[2] !== nothing ? (:solid, length(m[2])) : m[3] !== nothing ? (:thick, length(m[3])) :
              m[4] !== nothing ? (:dotted, length(m[4])) : (:hidden, 1)
    # A line with no arrow needs three dashes. Two dashes start a line with text in it.
    whole = kind in (:dotted, :hidden) || m[6] !== nothing || n >= 3
    if whole
      len = kind in (:dotted, :hidden) ? n : m[6] !== nothing ? n - 1 : n - 2
      edge = Edge("", "", "", kind, end_of(m[1]), end_of(m[6]), max(1, len), Dict{String,String}())
      rest = SubString(s, ncodeunits(m.match) + 1)
    end
  end
  if edge === nothing
    for (pattern, kind) in OPEN_LINK
      m = match(pattern, s)
      m === nothing && continue
      n = length(m[3])
      len = kind == :dotted ? n : m[4] !== nothing ? n - 1 : n - 2
      edge = Edge("", "", plain(m[2]), kind, end_of(m[1]), end_of(m[4]), max(1, len), Dict{String,String}())
      rest = SubString(s, ncodeunits(m.match) + 1)
      break
    end
  end
  edge === nothing && return nothing
  # The text can come after the line too, between two bars
  said = match(r"^\s*\|([^|]*)\|", rest)
  if said !== nothing
    edge.text = plain(said[1])
    rest = SubString(rest, ncodeunits(said.match) + 1)
  end
  edge, rest
end

"The Chart that `code` describes"
read_chart(code::AbstractString) = begin
  lines, _ = statements(code)
  chart = Chart(:TB, Node[], Dict{String,Int}(), Group[], Edge[], Dict{String,Dict{String,String}}(), Dict{String,String}(), Chain[])
  open = Int[]   # the subgraphs that haven't closed yet
  first_line = true
  node!(id, shape, text, classes) = begin
    i = get!(chart.named, id) do
      push!(chart.nodes, Node(id, id, :rect, String[], Dict{String,String}(), 0))
      length(chart.nodes)
    end
    node = chart.nodes[i]
    shape === nothing || (node.shape = shape)
    text === nothing || (node.text = text)
    append!(node.classes, classes)
    # A box belongs to the subgraph that names it
    isempty(open) || node.group != 0 || (node.group = open[end])
    id
  end
  for (n, line) in lines, s in pieces(line)
    if first_line
      first_line = false
      m = match(r"^(?:graph|flowchart)(?:-elk)?\b\s*(\w+)?\s*(.*)$", s)
      m === nothing && throw(Problem(n, "A flowchart starts with `flowchart` or `graph`"))
      m[1] === nothing || (chart.dir = get(DIRS, uppercase(m[1]), :TB))
      continue
    end
    word = match(r"^(\w+)\b\s*(.*)$", s)
    key, rest = word === nothing ? ("", s) : (word[1], word[2])
    if key == "subgraph"
      m = match(r"^([^\s\[]+)?\s*(?:\[(.*)\])?\s*$", rest)
      id, title = m === nothing || m[2] === nothing ? (String(rest), plain(rest)) : (String(something(m[1], m[2])), plain(m[2]))
      push!(chart.groups, Group(id, title, isempty(open) ? 0 : open[end], nothing, String[], Dict{String,String}(), n, 0))
      push!(open, length(chart.groups))
    elseif s == "end"
      isempty(open) && throw(Problem(n, "This `end` closes nothing"))
      chart.groups[pop!(open)].closes = n
    elseif key == "direction"
      way = get(DIRS, uppercase(strip(rest)), nothing)
      way === nothing && throw(Problem(n, "A direction is TB, BT, LR or RL"))
      isempty(open) ? (chart.dir = way) : (chart.groups[open[end]].dir = way)
    elseif key == "style"
      m = match(r"^(\S+)\s+(.*)$", rest)
      m === nothing && throw(Problem(n, "`style` needs a name, then its styles"))
      for id in split(m[1], ',')
        g = findfirst(g -> g.id == id, chart.groups)
        merge!(g === nothing ? chart.nodes[chart.named[node!(String(id), nothing, nothing, String[])]].style : chart.groups[g].style, styles(m[2]))
      end
    elseif key == "classDef"
      m = match(r"^(\S+)\s+(.*)$", rest)
      m === nothing && throw(Problem(n, "`classDef` needs a name, then its styles"))
      foreach(name -> chart.classes[String(name)] = styles(m[2]), split(m[1], ','))
    elseif key == "class"
      m = match(r"^(\S+)\s+([\w-]+)", rest)
      m === nothing && throw(Problem(n, "`class` needs the names of boxes, then the name of a class"))
      for id in split(m[1], ',')
        g = findfirst(g -> g.id == id, chart.groups)
        g === nothing ? node!(String(id), nothing, nothing, [String(m[2])]) : push!(chart.groups[g].classes, String(m[2]))
      end
    elseif key == "linkStyle"
      m = match(r"^(\S+)\s+(.*)$", rest)
      m === nothing && throw(Problem(n, "`linkStyle` needs the numbers of lines, then their styles"))
      for which in split(m[1], ',')
        i = tryparse(Int, which)
        i === nothing ? merge!(chart.links, styles(m[2])) : i < length(chart.edges) && merge!(chart.edges[i+1].style, styles(m[2]))
      end
    elseif key in ("click", "accTitle", "accDescr")
      # What a click does, and what a diagram says to someone who can't see it, aren't drawn
    else
      # Boxes with lines between them: A & B --> C --> D
      rest = SubString(s)
      # How many code units of the line come before what's left of this part of it
      stop = s.offset + ncodeunits(s)
      at() = stop - ncodeunits(rest)
      chain = Chain(n, line, Vector{Named}[], Linked[], length(chart.edges) + 1)
      from = String[]
      pending = nothing   # the line that came after the boxes before
      while true
        group = Named[]
        while true
          start = at()
          id, shape, text, classes, rest, look = read_node(rest, n)
          node!(id, shape, text, classes)
          shown = start + ncodeunits(id)
          push!(group, Named(id, text, classes, start+1:at(), shown+1:shown+look))
          m = match(r"^\s*&\s*", rest)
          m === nothing && break
          rest = SubString(rest, ncodeunits(m.match) + 1)
        end
        push!(chain.groups, group)
        if pending !== nothing
          for a in from, b in group
            push!(chart.edges, Edge(a, b.id, pending.text, pending.kind, pending.tail, pending.head, pending.len, Dict{String,String}()))
          end
        end
        rest = lstrip(rest)
        isempty(rest) && break
        start = at()
        found = read_link(rest)
        found === nothing && throw(Problem(n, "A line like --> was expected at \"$(first(rest, 20))\""))
        pending, rest = found
        push!(chain.links, Linked(pending, start+1:at()))
        rest = lstrip(rest)
        isempty(rest) && throw(Problem(n, "A line needs a box at its end"))
        from = [b.id for b in group]
      end
      push!(chart.chains, chain)
    end
  end
  chart
end

"What the styles of a box come to: its classes' styles, then its own"
resolved(chart::Chart, classes, own) = begin
  out = copy(get(chart.classes, "default", Dict{String,String}()))
  foreach(c -> merge!(out, get(chart.classes, c, Dict{String,String}())), classes)
  merge!(out, own)
end

"How wide and how tall a box of the shape `shape` is around a label that's `w` by `h`"
room(shape::Symbol, w, h, u) = begin
  wide, tall = w + 2.2u, h + 1.3u
  shape == :diamond ? (tall = h + 2.4u; (w * tall / (tall - h) + u, tall)) :
  shape == :circle ? (d = hypot(w, h) + 1.2u; (d, d)) :
  shape == :double_circle ? (d = hypot(w, h) + 2.1u; (d, d)) :
  shape == :stadium ? (wide + 0.6u, tall) :
  shape == :subroutine ? (wide + 1.2u, tall) :
  shape == :cylinder ? (wide, tall + 1.1u) :
  shape == :hexagon ? (wide + 0.5tall, tall) :
  shape == :flag ? (wide + 0.6u, tall) :
  shape in (:lean_right, :lean_left, :trapezoid, :trapezoid_alt) ? (wide + 0.7tall, tall) : (max(wide, 2.6u), tall)
end

"Where a line stops when it meets a box of the shape `shape`"
meets(shape::Symbol) = shape == :diamond ? :diamond : shape in (:circle, :double_circle) ? :circle : :rect

"The picture of the flowchart that `code` describes, with its text measured by `pen`"
flowchart(code::AbstractString, pen::Pen) = begin
  chart = read_chart(code)
  _, title = statements(code)
  u = pen.size
  boxes, links = Box[], Link[]
  # A subgraph is a box that other boxes are in
  group_box = Int[]
  group_label = Label[]
  for g in chart.groups
    l = label(pen, g.title, most=22u, size=0.92u)
    push!(group_label, l)
    push!(boxes, Box(max(l.w + 2u, 5u), l.h + 2.4u; inside=g.inside == 0 ? 0 : group_box[g.inside], dir=something(g.dir, chart.dir),
                     head=isempty(l.lines) ? 0.0 : l.h + 0.2u, least=l.w + 2u))
    push!(group_box, length(boxes))
  end
  group_named = Dict(g.id => group_box[i] for (i, g) in enumerate(chart.groups))
  node_box = Dict{String,Int}()
  node_label = Dict{String,Label}()
  for node in chart.nodes
    # A name that a subgraph has is that subgraph, so that a line can end at it
    haskey(group_named, node.id) && continue
    style = resolved(chart, node.classes, node.style)
    l = label(pen, node.text, most=15u, bold=get(style, "font-weight", "") == "bold", italic=get(style, "font-style", "") == "italic")
    node_label[node.id] = l
    w, h = room(node.shape, l.w, l.h, u)
    push!(boxes, Box(w, h; shape=meets(node.shape), inside=node.group == 0 ? 0 : group_box[node.group]))
    node_box[node.id] = length(boxes)
  end
  box_of(id) = get(() -> node_box[id], group_named, id)
  edge_label = Label[]
  for e in chart.edges
    l = label(pen, e.text, most=13u, size=0.92u)
    push!(edge_label, l)
    push!(links, Link(box_of(e.from), box_of(e.to); lw=isempty(l.lines) ? 0.0 : l.w + 0.8u, lh=isempty(l.lines) ? 0.0 : l.h + 0.3u, len=e.len))
  end
  w, h = arrange!(boxes, links; dir=chart.dir, nodesep=2.6u, ranksep=3.2u, pad=1.1u)

  items, parts = Any[], Part[]
  # Room around it all, so that the edge of a box at the side isn't cut off, and room at the top for a title
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.4u
  ox = edge + max(0.0, (heading.w - w) / 2)
  oy = edge + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u)
  isempty(heading.lines) || write!(items, heading, ox + w / 2, edge + heading.h / 2)
  for (i, g) in enumerate(chart.groups)
    b = boxes[group_box[i]]
    fill, line, thick, dash, text = look(resolved(chart, g.classes, g.style), u; fill=:group, line=:line)
    push!(items, Shape(:round, ox + b.x - b.w / 2, oy + b.y - b.h / 2, b.w, b.h; fill, line, thick, dash))
    write!(items, group_label[i], ox + b.x, oy + b.y - b.h / 2 + 0.45u + group_label[i].h / 2, colour=text == :text ? :dim : text)
    push!(parts, labelled(:group, i, (ox + b.x - b.w / 2, oy + b.y - b.h / 2, b.w, b.h), group_label[i],
                          ox + b.x, oy + b.y - b.h / 2 + 0.45u + max(group_label[i].h, 1.35u) / 2; shape=:round))
  end
  moved(p) = (p[1] + ox, p[2] + oy)
  for (i, e) in enumerate(chart.edges)
    l = links[i]
    (e.kind == :hidden || isempty(l.path)) && continue
    style = merge(chart.links, e.style)
    colour = haskey(style, "stroke") ? something(paint(style["stroke"]), :link) : :link
    thick = e.kind == :thick ? 0.2u : 0.09u
    if haskey(style, "stroke-width")
      n = tryparse(Float64, replace(style["stroke-width"], r"[a-z%\s]" => ""))
      n === nothing || (thick = n * u / 16)
    end
    around = isempty(edge_label[i].lines) ? NTuple{4,Float64}[] : [(ox + l.lx - l.lw / 2 + 0.15u, oy + l.ly - l.lh / 2, l.lw - 0.3u, l.lh)]
    push!(items, Stroke(moved.(l.path); curved=true, colour, thick, dash=e.kind == :dotted ? :dotted : :solid, from=e.tail, to=e.head, tip=0.75u, around))
    write!(items, edge_label[i], ox + l.lx, oy + l.ly, colour=haskey(style, "color") ? something(paint(style["color"]), :text) : :text)
    # A line's words are in its label, or at its middle when it has none
    path = flat(moved.(l.path))
    words = isempty(edge_label[i].lines) ? halfway(path) : (ox + l.lx, oy + l.ly)
    room = isempty(edge_label[i].lines) ? (words[1], words[2], 0.0, 0.0) : (ox + l.lx - l.lw / 2, oy + l.ly - l.lh / 2, l.lw, l.lh)
    push!(parts, labelled(:line, i, room, edge_label[i], words...; path))
  end
  for node in chart.nodes
    haskey(node_box, node.id) || continue
    b = boxes[node_box[node.id]]
    fill, line, thick, dash, text = look(resolved(chart, node.classes, node.style), u)
    x, y = ox + b.x - b.w / 2, oy + b.y - b.h / 2
    push!(items, Shape(node.shape, x, y, b.w, b.h; fill, line, thick, dash))
    # The text of a drum is under its lid, and the text of a flag is clear of its notch
    dx = node.shape == :flag ? 0.3u : 0.0
    dy = node.shape == :cylinder ? 0.3u : 0.0
    write!(items, node_label[node.id], ox + b.x + dx, oy + b.y + dy, colour=text)
    push!(parts, labelled(:box, node.id, (x, y, b.w, b.h), node_label[node.id], ox + b.x + dx, oy + b.y + dy; shape=node.shape))
  end
  # A click chooses a box before a line, and a line before the box round some boxes: the smallest of those first
  order(p::Part) = p.kind == :box ? (1, 0.0) : p.kind == :line ? (2, 0.0) : (3, p.box[3] * p.box[4])
  Picture(max(w, heading.w) + 2edge, oy + h + edge, items, sort(parts, by=order))
end

# --- changing a flowchart ---------------------------------------------------------
#
# The parts of a flowchart that can be selected are its boxes, each a :box with
# its name, its lines, each a :line with its number among the lines, and the
# boxes round some boxes, each a :group with its number among those.

const SHAPE_NAMES = ["Box" => :rect, "Round box" => :round, "Pill" => :stadium, "Diamond" => :diamond, "Circle" => :circle,
                     "Hexagon" => :hexagon, "Drum" => :cylinder, "Box with bars" => :subroutine, "Leaning box" => :lean_right, "Flag" => :flag]
const LINE_LOOKS = ["Arrow" => (:solid, :none, :arrow), "Line with no arrow" => (:solid, :none, :none), "Dotted arrow" => (:dotted, :none, :arrow),
                    "Thick arrow" => (:thick, :none, :arrow), "Arrow at both ends" => (:solid, :arrow, :arrow)]
const WAY_NAMES = ["Down" => "TD", "Across" => "LR", "Up" => "BT", "Across, from the right" => "RL"]

"What opens and what closes a box of the shape `shape` in the code"
brackets(shape::Symbol) = (i = findfirst(s -> s[3] == shape, SHAPES); i === nothing ? ("[", "]") : (SHAPES[i][1], SHAPES[i][2]))

"A line between two boxes as the code writes it, with its text after it between two bars"
link_text(kind::Symbol, tail::Symbol, head::Symbol, len::Int, text::AbstractString) = begin
  mark(m, left) = m == :arrow ? (left ? "<" : ">") : m == :circle ? "o" : m == :cross ? "x" : ""
  n = max(1, len)
  body = kind == :dotted ? "-" * "."^n * "-" : kind == :hidden ? "~~~" : (kind == :thick ? "=" : "-")^(n + (head == :none ? 2 : 1))
  said = isempty(strip(text)) ? "" : "|" * quoted(replace(text, "|" => "#124;")) * "|"
  mark(tail, true) * body * mark(head, false) * said
end

"A name for a new box that no box or group has: a capital letter, or N with a number once the letters are used"
fresh(chart::Chart) = begin
  taken = union(Set(keys(chart.named)), Set(g.id for g in chart.groups))
  for c in 'A':'Z'
    string(c) in taken || return string(c)
  end
  n = 1
  while "N$n" in taken
    n += 1
  end
  "N$n"
end

"""
Where the code gives the box `id` its shape and its text: the chain and the
place in it. That's the last place that gives it text, or the first place that
names it when none does. It's nothing for a box that only a style names.
"""
spot(chart::Chart, id) = begin
  found = nothing
  for c in chart.chains, g in c.groups, b in g
    b.id == id || continue
    (found === nothing || !isempty(b.look)) && (found = (c, b))
  end
  found
end

"`code` with the box `id` given the shape `shape` and the text `text`"
relook(code, chart::Chart, id, shape::Symbol, text) = begin
  open, close = brackets(shape)
  look = open * quoted(text) * close
  found = spot(chart, id)
  found === nothing && return added(code, id * look)
  c, b = found
  # A box with no shape yet gets it straight after its name
  at = isempty(b.look) ? (b.at.start+ncodeunits(id):b.at.start+ncodeunits(id)-1) : b.look
  relined(code, Dict(c.n => [spliced(c.line, at, look)]))
end

"""
The line of the chart with the number `i`, where the code draws it: the number
of its chain, the number of its link in the chain, and its place among the
lines that the link draws, which is more than one when an & is beside it.
"""
link_of(chart::Chart, i::Int) = begin
  for (ci, c) in enumerate(chart.chains)
    n = c.first
    for k in eachindex(c.links)
      many = length(c.groups[k]) * length(c.groups[k+1])
      i < n + many && return (ci, k, i - n + 1)
      n += many
    end
  end
  nothing
end

"Some of the groups of a chain that come one after another, with the links between them"
struct Run
  groups::Vector{Vector{Named}}
  links::Vector{Linked}
end

"A run as the code writes it"
written(c::Chain, r::Run) = begin
  out = join((cut(c.line, b.at) for b in r.groups[1]), " & ")
  for (k, l) in enumerate(r.links)
    out *= " " * cut(c.line, l.at) * " " * join((cut(c.line, b.at) for b in r.groups[k+1]), " & ")
  end
  out
end

"True for a run that only names a box, and gives it no shape, text or class"
bare(r::Run) = length(r.groups) == 1 && length(r.groups[1]) == 1 && isempty(r.groups[1][1].look) && isempty(r.groups[1][1].classes)

"The place `b` with only the name of its box"
only_name(b::Named) = Named(b.id, nothing, String[], b.at.start:b.at.start+ncodeunits(b.id)-1, 1:0)

"""
`code` with some of its chains written again. `new` gives the runs that go in
place of the chain with each number. A run that only names a box is left out
when the box is still named somewhere else. So a box never goes with a line
that's taken away, and no line is left that says nothing.
"""
rechained(code, chart::Chart, new::Dict{Int,Vector{Run}}) = begin
  named = Set{String}()
  for (i, c) in enumerate(chart.chains), r in get(new, i, [Run(c.groups, c.links)])
    haskey(new, i) && bare(r) && continue
    foreach(g -> foreach(b -> push!(named, b.id), g), r.groups)
  end
  whole = Dict{Int,Vector{String}}()   # the lines that a chain was all of
  part = Dict{Int,String}()            # the lines that hold more than a chain, as they are so far
  # The last chain of a line first, so that the places of the ones before it stay right
  for i in sort(collect(keys(new)), rev=true)
    c = chart.chains[i]
    runs = filter(new[i]) do r
      bare(r) || return true
      id = r.groups[1][1].id
      id in named && return false
      push!(named, id)
      true
    end
    at = c.groups[1][1].at.start:c.groups[end][end].at.stop
    if at == 1:ncodeunits(c.line)
      whole[c.n] = [written(c, r) for r in runs]
    else
      part[c.n] = spliced(get(part, c.n, c.line), at, join((written(c, r) for r in runs), "; "))
    end
  end
  for (n, line) in part
    left = join(pieces(line), "; ")
    whole[n] = isempty(left) ? String[] : [left]
  end
  relined(code, whole)
end

"`code` without the box `id`, the lines that end at it and the styles that name it"
without_box(code, chart::Chart, id) = begin
  new = Dict{Int,Vector{Run}}()
  for (i, c) in enumerate(chart.chains)
    any(b -> b.id == id, Iterators.flatten(c.groups)) || continue
    runs, groups, links = Run[], Vector{Named}[], Linked[]
    for (k, g) in enumerate(c.groups)
      g = filter(b -> b.id != id, g)
      if isempty(g)
        isempty(groups) || push!(runs, Run(groups, links))
        groups, links = Vector{Named}[], Linked[]
      else
        isempty(groups) || push!(links, c.links[k-1])
        push!(groups, g)
      end
    end
    isempty(groups) || push!(runs, Run(groups, links))
    new[i] = runs
  end
  code = rechained(code, chart, new)
  # A style, a class or a click that names only this box goes too
  gone = Dict{Int,Vector{String}}()
  for (n, line) in statements(code)[1]
    m = match(r"^(style|class|click)\s+(\S+)(.*)$", line)
    m === nothing && continue
    ids = split(m[2], ',')
    id in ids || continue
    left = filter(!=(id), ids)
    gone[n] = isempty(left) ? String[] : [m[1] * " " * join(left, ",") * m[3]]
  end
  relined(code, gone)
end

"`code` without the line of the chart that has the number `i`. The boxes at its ends stay."
without_line(code, chart::Chart, i::Int) = begin
  ci, k, j = link_of(chart, i)
  c = chart.chains[ci]
  runs = [Run(c.groups[1:k], c.links[1:k-1]), Run(c.groups[k+1:end], c.links[k+1:end])]
  # With an & beside it, the link draws more lines than this one. Each of the others gets a line of code of its own.
  pairs = [(a, b) for a in c.groups[k] for b in c.groups[k+1]]
  for (p, (a, b)) in enumerate(pairs)
    p == j || push!(runs, Run([[only_name(a)], [only_name(b)]], [c.links[k]]))
  end
  rechained(code, chart, Dict(ci => runs))
end

"The words that a part of the flowchart `code` shows, as you type them"
flow_said(code, kind::Symbol, key) = begin
  chart = read_chart(code)
  typed(kind == :box ? chart.nodes[chart.named[key]].text : kind == :line ? chart.edges[key].text : kind == :group ? chart.groups[key].title : "")
end

"The flowchart `code` with `text` as the words of one of its parts"
flow_reword(code, kind::Symbol, key, text) = begin
  chart = read_chart(code)
  text = strip(text)
  if kind == :box
    isempty(text) ? code : relook(code, chart, key, chart.nodes[chart.named[key]].shape, text)
  elseif kind == :line
    ci, k, _ = link_of(chart, key)
    c = chart.chains[ci]
    e = c.links[k].edge
    relined(code, Dict(c.n => [spaced(c.line, c.links[k].at, link_text(e.kind, e.tail, e.head, e.len, text))]))
  elseif kind == :group
    isempty(text) && return code
    g = chart.groups[key]
    line = strip(split(code, '\n')[g.opens])
    m = match(r"^subgraph\s+(.*)$", line)
    m === nothing && return code
    named = match(r"^([^\s\[]+)?\s*\[(.*)\]\s*$", m[1])
    # A group keeps its name, which a line can end at, and its text goes after that in brackets
    new = named !== nothing ? something(named[1], "") * "[" * quoted(text, always=true) * "]" :
          occursin(r"\s", m[1]) ? quoted(text) : m[1] * "[" * quoted(text, always=true) * "]"
    relined(code, Dict(g.opens => ["subgraph " * new]))
  else
    code
  end
end

"What you can do to the flowchart `code` while the part `key` of the kind `kind` is selected, or with `kind` :none while nothing is"
flow_tools(code, kind::Symbol, key) =
  kind == :box ? [Tool(:add, "node-plus", "Add a box after this one"),
                  Tool(:join, "bezier2", "Draw a line from this box: click the box that it goes to", target=true),
                  Tool(:shape, "pentagon", "Change the shape of the box", choices=SHAPE_NAMES),
                  Tool(:delete, "trash3", "Take the box away  ⌫")] :
  kind == :line ? [Tool(:look, "arrow-right", "Change how the line looks", choices=LINE_LOOKS),
                   Tool(:turn, "arrow-left-right", "Turn the line round"),
                   Tool(:delete, "trash3", "Take the line away  ⌫")] :
  kind == :group ? [Tool(:delete, "trash3", "Take away the box round these boxes  ⌫")] :
  [Tool(:add, "plus-square", "Add a box"), Tool(:way, "signpost-split", "Change which way the chart goes", choices=WAY_NAMES)]

"""
Use a tool on the flowchart `code`. `arg` is the choice, or the part that was
clicked, for a tool that needs one. Returns the new code, the part that's
selected after it, and whether the words of that part are typed next.
"""
flow_use(code, tool::Symbol, kind::Symbol, key, arg) = begin
  chart = read_chart(code)
  same = (code, kind == :none ? nothing : (kind, key), false)
  if tool == :add
    id = fresh(chart)
    (added(code, kind == :box ? "$key --> $id[New box]" : "$id[New box]"), (:box, id), true)
  elseif tool == :join && kind == :box
    (arg isa Tuple && arg[1] in (:box, :group)) || return same
    to = arg[1] == :box ? arg[2] : chart.groups[arg[2]].id
    occursin(r"^[\p{L}\p{N}_]+(?:[-.][\p{L}\p{N}_]+)*$", to) || return same
    (added(code, "$key --> $to"), (:line, length(chart.edges) + 1), false)
  elseif tool == :shape && kind == :box
    arg isa Symbol || return same
    (relook(code, chart, key, arg, chart.nodes[chart.named[key]].text), (kind, key), false)
  elseif tool == :look && kind == :line
    arg isa Tuple || return same
    ci, k, _ = link_of(chart, key)
    c = chart.chains[ci]
    e = c.links[k].edge
    (relined(code, Dict(c.n => [spaced(c.line, c.links[k].at, link_text(arg[1], arg[2], arg[3], e.len, e.text))])), (kind, key), false)
  elseif tool == :turn && kind == :line
    ci, k, _ = link_of(chart, key)
    c = chart.chains[ci]
    if length(c.groups) == 2 && all(g -> length(g) == 1, c.groups)
      # A line of code that draws only this line: its two boxes change places
      a, b = c.groups[1][1], c.groups[2][1]
      text = cut(c.line, b.at) * " " * cut(c.line, c.links[1].at) * " " * cut(c.line, a.at)
      return (relined(code, Dict(c.n => [spliced(c.line, a.at.start:b.at.stop, text)])), (kind, key), false)
    end
    e = chart.edges[key]
    less = without_line(code, chart, key)
    (added(less, e.to * " " * cut(c.line, c.links[k].at) * " " * e.from), (:line, length(chart.edges)), false)
  elseif tool == :delete
    kind == :box ? (without_box(code, chart, key), nothing, false) :
    kind == :line ? (without_line(code, chart, key), nothing, false) :
    kind == :group ? (g = chart.groups[key]; (relined(code, Dict(n => String[] for n in (g.opens, g.closes) if n > 0)), nothing, false)) : same
  elseif tool == :way
    n, line = statements(code)[1][1]
    m = match(r"^((?:graph|flowchart)(?:-elk)?)\b\s*(\w+)?(.*)$", line)
    (m === nothing || !(arg isa AbstractString)) && return same
    (relined(code, Dict(n => [m[1] * " " * arg * m[3]])), same[2], false)
  else
    same
  end
end

"How the parts of a flowchart are changed. See `EDITORS` in main.jl."
const flowchart_edits = (said=flow_said, reword=flow_reword, tools=flow_tools, use=flow_use)

export flowchart, flowchart_edits
