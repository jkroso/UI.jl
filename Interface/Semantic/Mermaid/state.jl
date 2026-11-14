# A state diagram: the states that something can be in, and how it goes from one to the next.
#
#     stateDiagram-v2
#       [*] --> Still
#       Still --> Moving : push
#       Moving --> Still : stop
#       Moving --> Crash
#       Crash --> [*]
#
# [*] is where it starts, as the start of an arrow, and where it ends, as the
# end of one. `state Name { … }` is a state with states in it. `state "Some
# text" as Name`, or `Name : Some text`, gives a state the text that it shows.
# `state Name <<choice>>` is a small diamond, and <<fork>> and <<join>> are
# bars. `note right of Name : text` puts a note beside a state. `direction LR`
# makes it go from left to right.

@use "./picture"...
@use "./graph" Box Link arrange! across

mutable struct State
  id::String
  text::Vector{String}
  kind::Symbol      # :state, :start, :stop, :choice, :bar or :group
  inside::Int       # the state that it's in, or 0
  dir::Union{Symbol,Nothing}
  classes::Vector{String}
end

const WAYS = Dict("TB" => :TB, "TD" => :TB, "BT" => :BT, "LR" => :LR, "RL" => :RL)

"The picture of the state diagram that `code` describes, with its text measured by `pen`"
state(code::AbstractString, pen::Pen) = begin
  lines, title = statements(code)
  u = pen.size
  states, named = State[], Dict{String,Int}()
  moves = Tuple{Int,Int,String}[]
  notes = Tuple{Int,Bool,String}[]   # the state that each note is beside, whether it's on its left, and its text
  styles_of = Dict{String,Dict{String,String}}()
  dir = :TB
  open = Int[]
  noting = nothing   # the note whose lines are being read
  within() = isempty(open) ? 0 : open[end]
  state!(name) = begin
    name = String(strip(name))
    classes = String[]
    if (m = match(r"^(.*?):::([\w-]+)$", name)) !== nothing
      name, classes = String(m[1]), [String(m[2])]
    end
    i = get!(named, name) do
      push!(states, State(name, String[], :state, within(), nothing, String[]))
      length(states)
    end
    append!(states[i].classes, classes)
    i
  end
  # [*] is a start or an end of the state that it's in. Each state has one of each at most.
  point!(start) = begin
    name = (start ? "start of " : "end of ") * string(within())
    i = get!(named, name) do
      push!(states, State(name, String[], start ? :start : :stop, within(), nothing, String[]))
      length(states)
    end
    i
  end
  for (n, line) in lines[2:end]
    if noting !== nothing
      if occursin(r"^end\s+note$"i, line)
        push!(notes, (noting[1], noting[2], join(noting[3], "\n")))
        noting = nothing
      else
        push!(noting[3], plain(line))
      end
    elseif (m = match(r"^direction\s+(\w+)$", line)) !== nothing
      way = get(WAYS, uppercase(m[1]), nothing)
      way === nothing && throw(Problem(n, "A direction is TB, BT, LR or RL"))
      isempty(open) ? (dir = way) : (states[open[end]].dir = way)
    elseif (m = match(r"^note\s+(left|right)\s+of\s+([^:]+?)\s*(?::\s*(.*))?$"i, line)) !== nothing
      i = state!(m[2])
      m[3] === nothing ? (noting = (i, lowercase(m[1]) == "left", String[])) : push!(notes, (i, lowercase(m[1]) == "left", plain(m[3])))
    elseif (m = match(r"^state\s+\"([^\"]*)\"\s+as\s+(\S+?)\s*(\{)?$", line)) !== nothing
      i = state!(m[2])
      states[i].text = [plain(m[1])]
      m[3] === nothing || (states[i].kind = :group; push!(open, i))
    elseif (m = match(r"^state\s+(\S+?)\s*<<(\w+)>>$", line)) !== nothing
      i = state!(m[1])
      states[i].kind = lowercase(m[2]) == "choice" ? :choice : :bar
    elseif (m = match(r"^state\s+(\S+?)\s*(\{)?$", line)) !== nothing
      i = state!(m[1])
      m[2] === nothing || (states[i].kind = :group; push!(open, i))
    elseif line == "}"
      isempty(open) && throw(Problem(n, "This } closes nothing"))
      pop!(open)
    elseif line == "--"
      # Two parts of a state that happen at once are drawn as one part
    elseif (m = match(r"^classDef\s+(\S+)\s+(.*)$", line)) !== nothing
      foreach(name -> styles_of[String(name)] = styles(m[2]), split(m[1], ','))
    elseif (m = match(r"^class\s+(\S+)\s+([\w-]+)$", line)) !== nothing
      foreach(name -> push!(states[state!(name)].classes, String(m[2])), split(m[1], ','))
    elseif occursin(r"^(accTitle|accDescr|hide|scale)\b", line)
      # Not drawn
    elseif (m = match(r"^(.+?)\s*-->\s*(.+?)\s*(?::\s*(.*))?$", line)) !== nothing
      a = strip(m[1]) == "[*]" ? point!(true) : state!(m[1])
      b = strip(m[2]) == "[*]" ? point!(false) : state!(m[2])
      push!(moves, (a, b, plain(something(m[3], ""))))
    elseif (m = match(r"^([^\s:]+)\s*:\s*(.*)$", line)) !== nothing
      push!(states[state!(m[1])].text, plain(m[2]))
    elseif occursin(r"^[^\s:]+$", line)
      state!(line)
    else
      throw(Problem(n, "\"$(first(line, 30))\" isn't a state or an arrow between two states"))
    end
  end
  isempty(open) || throw(Problem(0, "A { is never closed"))
  isempty(states) && return Picture(0.0, 0.0, Any[])

  small = 0.92u
  boxes, links = Box[], Link[]
  labels = Label[]
  for s in states
    l = label(pen, isempty(s.text) ? s.id : join(s.text, "\n"), most=15u, bold=s.kind == :group, size=s.kind == :group ? small : u)
    s.kind in (:start, :stop, :choice, :bar) && (l = label(pen, ""))
    push!(labels, l)
    way = something(s.dir, s.inside == 0 ? dir : something(states[s.inside].dir, dir))
    push!(boxes, s.kind == :group ? Box(max(l.w + 2u, 5u), l.h + 2.4u; inside=s.inside, dir=way, head=l.h + 0.7u, least=l.w + 2u) :
                 s.kind == :start ? Box(1.1u, 1.1u; shape=:circle, inside=s.inside) :
                 s.kind == :stop ? Box(1.4u, 1.4u; shape=:circle, inside=s.inside) :
                 s.kind == :choice ? Box(1.8u, 1.8u; shape=:diamond, inside=s.inside) :
                 s.kind == :bar ? (across(way) ? Box(0.55u, 5u; inside=s.inside) : Box(5u, 0.55u; inside=s.inside)) :
                 Box(max(l.w + 2u, 3.2u), l.h + 1.2u; inside=s.inside))
  end
  move_labels = Label[]
  for (a, b, text) in moves
    l = label(pen, text, most=13u, size=small)
    push!(move_labels, l)
    push!(links, Link(a, b; lw=isempty(l.lines) ? 0.0 : l.w + 0.8u, lh=isempty(l.lines) ? 0.0 : l.h + 0.3u))
  end
  # A note and its state go side by side in a box that isn't drawn. A line that isn't drawn puts them in order.
  note_boxes = Tuple{Int,Label}[]
  for (i, on_left, text) in notes
    l = label(pen, text, most=14u, size=small)
    push!(boxes, Box(0.0, 0.0; inside=boxes[i].inside, dir=:LR, pad=0.0))
    pair = length(boxes)
    boxes[i].inside = pair
    push!(boxes, Box(l.w + 1.4u, l.h + 0.8u; inside=pair))
    push!(note_boxes, (length(boxes), l))
    push!(links, on_left ? Link(length(boxes), i) : Link(i, length(boxes)))
  end
  w, h = arrange!(boxes, links; dir, nodesep=2.4u, ranksep=3u, pad=1.1u)

  items = Any[]
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.4u
  ox = edge + max(0.0, (heading.w - w) / 2)
  oy = edge + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u)
  isempty(heading.lines) || write!(items, heading, ox + w / 2, edge + heading.h / 2)
  look_of(s) = begin
    style = Dict{String,String}()
    foreach(c -> merge!(style, get(styles_of, c, Dict{String,String}())), s.classes)
    style
  end
  corner(b) = (ox + b.x - b.w / 2, oy + b.y - b.h / 2)
  for (i, s) in enumerate(states)
    s.kind == :group || continue
    b, l = boxes[i], labels[i]
    x, y = corner(b)
    fill, line, thick, dash, text = look(look_of(s), u; fill=:group, line=:edge)
    push!(items, Shape(:round, x, y, b.w, b.h; fill, line, thick, dash))
    write!(items, l, ox + b.x, y + 0.35u + l.h / 2, colour=text)
    push!(items, Stroke([(x, y + l.h + 0.7u), (x + b.w, y + l.h + 0.7u)]; colour=line, thick))
  end
  moved(p) = (p[1] + ox, p[2] + oy)
  for (i, (a, b, _)) in enumerate(moves)
    l = links[i]
    isempty(l.path) && continue
    around = isempty(move_labels[i].lines) ? NTuple{4,Float64}[] : [(ox + l.lx - l.lw / 2 + 0.15u, oy + l.ly - l.lh / 2, l.lw - 0.3u, l.lh)]
    push!(items, Stroke(moved.(l.path); curved=true, thick=0.09u, to=:arrow, tip=0.75u, around))
    write!(items, move_labels[i], ox + l.lx, oy + l.ly)
  end
  for (k, (at, l)) in enumerate(note_boxes)
    b = boxes[at]
    x, y = corner(b)
    # A dotted line ties the note to its state
    other = boxes[notes[k][1]]
    side = b.x > other.x ? 1 : -1
    push!(items, Stroke([(ox + other.x + side * other.w / 2, oy + b.y), (ox + b.x - side * b.w / 2, oy + b.y)]; colour=:note_edge, thick=0.08u, dash=:dotted))
    push!(items, Shape(:rect, x, y, b.w, b.h; fill=:note, line=:note_edge, thick=0.07u))
    write!(items, l, ox + b.x, oy + b.y)
  end
  for (i, s) in enumerate(states)
    s.kind == :group && continue
    b = boxes[i]
    x, y = corner(b)
    if s.kind == :start
      push!(items, Shape(:circle, x, y, b.w, b.h; fill=:link, line=nothing))
    elseif s.kind == :stop
      push!(items, Shape(:circle, x, y, b.w, b.h; fill=:surface, line=:link, thick=0.09u))
      push!(items, Shape(:circle, x + 0.3u, y + 0.3u, b.w - 0.6u, b.h - 0.6u; fill=:link, line=nothing))
    elseif s.kind == :bar
      push!(items, Shape(:rect, x, y, b.w, b.h; fill=:link, line=nothing))
    else
      fill, line, thick, dash, text = look(look_of(s), u)
      push!(items, Shape(s.kind == :choice ? :diamond : :round, x, y, b.w, b.h; fill, line, thick, dash))
      write!(items, labels[i], ox + b.x, oy + b.y, colour=text)
    end
  end
  Picture(max(w, heading.w) + 2edge, oy + h + edge, items)
end

export state
