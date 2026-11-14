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

mutable struct Chart
  dir::Symbol
  nodes::Vector{Node}
  named::Dict{String,Int}
  groups::Vector{Group}
  edges::Vector{Edge}
  classes::Dict{String,Dict{String,String}}
  links::Dict{String,String}   # the style for every line
end

const DIRS = Dict("TB" => :TB, "TD" => :TB, "BT" => :BT, "LR" => :LR, "RL" => :RL)

"The parts of `line` that a ; is between. A ; in quotes or in brackets is part of a label."
pieces(line) = begin
  out, depth, quoted, from = String[], 0, false, firstindex(line)
  for (i, c) in pairs(line)
    if c == '"'
      quoted = !quoted
    elseif !quoted && c in "[({"
      depth += 1
    elseif !quoted && c in "])}"
      depth = max(0, depth - 1)
    elseif !quoted && depth == 0 && c == ';'
      push!(out, strip(line[from:prevind(line, i)]))
      from = nextind(line, i)
    end
  end
  push!(out, strip(line[from:end]))
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
nothing, the classes and what's left of `s`.
"""
read_node(s, line) = begin
  m = match(ID, s)
  m === nothing && throw(Problem(line, "A box's name was expected at \"$(first(s, 20))\""))
  id, rest = String(m.match), SubString(s, ncodeunits(m.match) + 1)
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
  classes = String[]
  while (c = match(r"^:::([\w-]+)", rest)) !== nothing
    push!(classes, c[1])
    rest = SubString(rest, ncodeunits(c.match) + 1)
  end
  id, shape, text, classes, rest
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
  chart = Chart(:TB, Node[], Dict{String,Int}(), Group[], Edge[], Dict{String,Dict{String,String}}(), Dict{String,String}())
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
      push!(chart.groups, Group(id, title, isempty(open) ? 0 : open[end], nothing, String[], Dict{String,String}()))
      push!(open, length(chart.groups))
    elseif s == "end"
      isempty(open) && throw(Problem(n, "This `end` closes nothing"))
      pop!(open)
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
      from = String[]
      pending = nothing   # the line that came after the boxes before
      while true
        group = String[]
        while true
          id, shape, text, classes, rest = read_node(rest, n)
          push!(group, node!(id, shape, text, classes))
          m = match(r"^\s*&\s*", rest)
          m === nothing && break
          rest = SubString(rest, ncodeunits(m.match) + 1)
        end
        if pending !== nothing
          for a in from, b in group
            push!(chart.edges, Edge(a, b, pending.text, pending.kind, pending.tail, pending.head, pending.len, Dict{String,String}()))
          end
        end
        rest = lstrip(rest)
        isempty(rest) && break
        found = read_link(rest)
        found === nothing && throw(Problem(n, "A line like --> was expected at \"$(first(rest, 20))\""))
        pending, rest = found
        rest = lstrip(rest)
        isempty(rest) && throw(Problem(n, "A line needs a box at its end"))
        from = group
      end
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

  items = Any[]
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
  end
  Picture(max(w, heading.w) + 2edge, oy + h + edge, items)
end

export flowchart
