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

"""
What the code of a state diagram says: its states, its moves from one state
to another, and its notes. The rest says where each is in the code:
`move_at` is the line of each move, `note_at` is the lines of each note,
`spans` is the lines that open and close each state that has states in it, by
its place among the states, and `turned` is the line that says which way the
whole diagram goes, or 0.
"""
read_states(code::AbstractString) = begin
  lines, title = statements(code)
  states, named = State[], Dict{String,Int}()
  moves = Tuple{Int,Int,String}[]
  notes = Tuple{Int,Bool,String}[]   # the state that each note is beside, whether it's on its left, and its text
  styles_of = Dict{String,Dict{String,String}}()
  move_at, note_at, spans, turned = Int[], UnitRange{Int}[], Dict{Int,Tuple{Int,Int}}(), 0
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
        push!(note_at, noting[4]:n)
        noting = nothing
      else
        push!(noting[3], plain(line))
      end
    elseif (m = match(r"^direction\s+(\w+)$", line)) !== nothing
      way = get(WAYS, uppercase(m[1]), nothing)
      way === nothing && throw(Problem(n, "A direction is TB, BT, LR or RL"))
      isempty(open) ? (dir = way; turned = n) : (states[open[end]].dir = way)
    elseif (m = match(r"^note\s+(left|right)\s+of\s+([^:]+?)\s*(?::\s*(.*))?$"i, line)) !== nothing
      i = state!(m[2])
      m[3] === nothing ? (noting = (i, lowercase(m[1]) == "left", String[], n)) : (push!(notes, (i, lowercase(m[1]) == "left", plain(m[3]))); push!(note_at, n:n))
    elseif (m = match(r"^state\s+\"([^\"]*)\"\s+as\s+(\S+?)\s*(\{)?$", line)) !== nothing
      i = state!(m[2])
      states[i].text = [plain(m[1])]
      m[3] === nothing || (states[i].kind = :group; push!(open, i); spans[i] = (n, 0))
    elseif (m = match(r"^state\s+(\S+?)\s*<<(\w+)>>$", line)) !== nothing
      i = state!(m[1])
      states[i].kind = lowercase(m[2]) == "choice" ? :choice : :bar
    elseif (m = match(r"^state\s+(\S+?)\s*(\{)?$", line)) !== nothing
      i = state!(m[1])
      m[2] === nothing || (states[i].kind = :group; push!(open, i); spans[i] = (n, 0))
    elseif line == "}"
      isempty(open) && throw(Problem(n, "This } closes nothing"))
      i = pop!(open)
      spans[i] = (spans[i][1], n)
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
      push!(move_at, n)
    elseif (m = match(r"^([^\s:]+)\s*:\s*(.*)$", line)) !== nothing
      push!(states[state!(m[1])].text, plain(m[2]))
    elseif occursin(r"^[^\s:]+$", line)
      state!(line)
    else
      throw(Problem(n, "\"$(first(line, 30))\" isn't a state or an arrow between two states"))
    end
  end
  isempty(open) || throw(Problem(0, "A { is never closed"))
  (; states, named, moves, notes, styles_of, dir, title, move_at, note_at, spans, turned)
end

"The picture of the state diagram that `code` describes, with its text measured by `pen`"
state(code::AbstractString, pen::Pen) = begin
  (; states, moves, notes, styles_of, dir, title) = read_states(code)
  u = pen.size
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

  items, parts = Any[], Part[]
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
    push!(parts, labelled(:state, s.id, (x, y, b.w, b.h), l, ox + b.x, y + 0.35u + l.h / 2; shape=:round))
  end
  moved(p) = (p[1] + ox, p[2] + oy)
  for (i, (a, b, _)) in enumerate(moves)
    l = links[i]
    isempty(l.path) && continue
    around = isempty(move_labels[i].lines) ? NTuple{4,Float64}[] : [(ox + l.lx - l.lw / 2 + 0.15u, oy + l.ly - l.lh / 2, l.lw - 0.3u, l.lh)]
    push!(items, Stroke(moved.(l.path); curved=true, thick=0.09u, to=:arrow, tip=0.75u, around))
    write!(items, move_labels[i], ox + l.lx, oy + l.ly)
    # A move's words are in its label, or at its middle when it has none
    path = flat(moved.(l.path))
    words = isempty(move_labels[i].lines) ? halfway(path) : (ox + l.lx, oy + l.ly)
    room = isempty(move_labels[i].lines) ? (words[1], words[2], 0.0, 0.0) : (ox + l.lx - l.lw / 2, oy + l.ly - l.lh / 2, l.lw, l.lh)
    push!(parts, labelled(:move, i, room, move_labels[i], words...; path))
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
    push!(parts, labelled(:note, k, (x, y, b.w, b.h), l, ox + b.x, oy + b.y))
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
    # A dot where it starts or ends isn't a part. The arrow that goes from it or to it is.
    s.kind in (:start, :stop) || push!(parts, labelled(:state, s.id, (x, y, b.w, b.h), labels[i], ox + b.x, oy + b.y;
                                                        shape=s.kind == :choice ? :diamond : s.kind == :bar ? :plain : :round))
  end
  # A click chooses a state or a note before an arrow, and an arrow before a state that has states in it: the smallest of those first
  held = Set(s.id for s in states if s.kind == :group)
  order(p::Part) = p.kind == :move ? (2, 0.0) : p.kind == :state && p.key in held ? (3, p.box[3] * p.box[4]) : (1, 0.0)
  Picture(max(w, heading.w) + 2edge, oy + h + edge, items, sort(parts, by=order))
end

# --- changing a state diagram -----------------------------------------------------
#
# The parts of a state diagram that can be selected are its states, each a
# :state with its name, the arrows from one state to another, each a :move
# with its number among them, and its notes, each a :note with its number.
# The dot where the diagram starts or ends is part of the arrow beside it.

const WAY_NAMES = ["Down" => "TB", "Across" => "LR", "Up" => "BT", "Across, from the right" => "RL"]
const MOVE = r"^(.+?)\s*-->\s*(.+?)\s*(?::\s*(.*))?$"

"The name of a state as a line of the code writes it, without the class after it"
named_by(text) = String(replace(strip(text), r":::[\w-]+$" => ""))

"A name for a new state that no state has: S with a number"
fresh_state(named) = begin
  n = 1
  while haskey(named, "S$n")
    n += 1
  end
  "S$n"
end

"The lines of `code` that say something, by their numbers"
said_lines(code) = Dict(statements(code)[1])

"The words that a part of the state diagram `code` shows, as you type them. A state that's a diamond or a bar shows none."
state_said(code, kind::Symbol, key) = begin
  r = read_states(code)
  if kind == :state
    s = r.states[r.named[key]]
    s.kind in (:choice, :bar) ? nothing : typed(isempty(s.text) ? s.id : join(s.text, "\n"))
  elseif kind == :move
    typed(r.moves[key][3])
  elseif kind == :note
    typed(r.notes[key][3])
  end
end

"The state diagram `code` with `text` as the words of one of its parts"
state_reword(code, kind::Symbol, key, text) = begin
  r = read_states(code)
  lines = said_lines(code)
  text = String(strip(replace(text, '\n' => "<br>")))
  if kind == :state
    isempty(text) && return code
    # The lines that give the state its words: `state "words" as Name`, and `Name : words`
    as, own, first_named = 0, Int[], 0
    for (n, line) in sort(collect(lines))
      if (m = match(r"^state\s+\"([^\"]*)\"\s+as\s+(\S+?)\s*(\{)?$", line)) !== nothing
        named_by(m[2]) == key && (as = n)
      elseif (m = match(r"^state\s+(\S+?)\s*(\{)?$", line)) !== nothing
        named_by(m[1]) == key && first_named == 0 && (first_named = n)
      elseif match(MOVE, line) === nothing && (m = match(r"^([^\s:]+)\s*:\s*(.*)$", line)) !== nothing
        named_by(m[1]) == key && push!(own, n)
      end
    end
    new = Dict{Int,Vector{String}}(n => String[] for n in own)
    if as != 0
      new[as] = [replace(lines[as], r"^state\s+\"[^\"]*\"" => "state " * quoted(text, always=true))]
    elseif haskey(r.spans, r.named[key])
      # A state with states in it gets its words on the line that opens it
      open = r.spans[r.named[key]][1]
      new[open] = ["state " * quoted(text, always=true) * " as " * key * " {"]
    elseif !isempty(own)
      new[own[1]] = [key * " : " * text]
    else
      text == key && return code
      # After the first line that names it, so that it stays in the state that it's in
      at = first_named != 0 ? first_named : findfirst(i -> key in (r.states[r.moves[i][1]].id, r.states[r.moves[i][2]].id), eachindex(r.moves))
      at === nothing && return added(code, key * " : " * text)
      n = first_named != 0 ? first_named : r.move_at[at]
      new[n] = [lines[n], key * " : " * text]
    end
    relined(code, new)
  elseif kind == :move
    n = r.move_at[key]
    m = match(MOVE, lines[n])
    relined(code, Dict(n => [strip(m[1]) * " --> " * strip(m[2]) * (isempty(text) ? "" : " : " * text)]))
  elseif kind == :note
    isempty(text) && return code
    at = r.note_at[key]
    m = match(r"^note\s+(left|right)\s+of\s+([^:]+?)\s*(?::.*)?$"i, lines[at.start])
    new = Dict{Int,Vector{String}}(n => String[] for n in at if haskey(lines, n))
    new[at.start] = ["note " * lowercase(m[1]) * " of " * m[2] * " : " * text]
    relined(code, new)
  else
    code
  end
end

"What you can do to the state diagram `code` while the part `key` of the kind `kind` is selected, or with `kind` :none while nothing is"
state_tools(code, kind::Symbol, key) =
  kind == :state ? [Tool(:add, "node-plus", "Add a state after this one"),
                    Tool(:join, "bezier2", "Draw an arrow from this state: click the state that it goes to", target=true),
                    Tool(:start, "record-circle", "It starts in this state"),
                    Tool(:stop, "stop-circle", "It ends after this state"),
                    Tool(:note, "sticky", "Add a note beside this state"),
                    Tool(:delete, "trash3", "Take the state away  ⌫")] :
  kind == :move ? [Tool(:turn, "arrow-left-right", "Turn the arrow round"), Tool(:delete, "trash3", "Take the arrow away  ⌫")] :
  kind == :note ? [Tool(:delete, "trash3", "Take the note away  ⌫")] :
  [Tool(:add, "plus-square", "Add a state"), Tool(:way, "signpost-split", "Change which way the diagram goes", choices=WAY_NAMES)]

"`code` without the state `id`: the lines that give it words, the arrows that end at it and its notes. The states in it stay."
without_state(code, r, id) = begin
  lines = said_lines(code)
  i = r.named[id]
  gone = Dict{Int,Vector{String}}()
  for (k, (a, b, _)) in enumerate(r.moves)
    (a == i || b == i) && (gone[r.move_at[k]] = String[])
  end
  for (k, note) in enumerate(r.notes), n in r.note_at[k]
    note[1] == i && haskey(lines, n) && (gone[n] = String[])
  end
  haskey(r.spans, i) && foreach(n -> n > 0 && (gone[n] = String[]), r.spans[i])
  for (n, line) in lines
    haskey(gone, n) && continue
    if (m = match(r"^state\s+(?:\"[^\"]*\"\s+as\s+)?(\S+?)\s*(?:<<\w+>>)?$", line)) !== nothing
      named_by(m[1]) == id && (gone[n] = String[])
    elseif (m = match(r"^class\s+(\S+)\s+([\w-]+)$", line)) !== nothing
      names = split(m[1], ',')
      id in names && (gone[n] = length(names) == 1 ? String[] : ["class " * join(filter(!=(id), names), ",") * " " * m[2]])
    elseif match(MOVE, line) === nothing && (m = match(r"^([^\s:]+)\s*(?::.*)?$", line)) !== nothing
      named_by(m[1]) == id && (gone[n] = String[])
    end
  end
  less = relined(code, gone)
  # A state that only an arrow to this one named stays, on a line of its own
  left = read_states(less).named
  lone = [s.id for s in r.states if s.id != id && !(s.kind in (:start, :stop)) && !haskey(left, s.id)]
  isempty(lone) ? less : added(less, lone...)
end

"""
Use a tool on the state diagram `code`. `arg` is the choice, or the part that
was clicked, for a tool that needs one. Returns the new code, the part that's
selected after it, and whether the words of that part are typed next.
"""
state_use(code, tool::Symbol, kind::Symbol, key, arg) = begin
  r = read_states(code)
  lines = said_lines(code)
  same = (code, kind == :none ? nothing : (kind, key), false)
  if tool == :add
    id = fresh_state(r.named)
    kind == :state ? (added(code, "$key --> $id", "$id : New state"), (:state, id), true) : (added(code, "$id : New state"), (:state, id), true)
  elseif tool == :join && kind == :state
    (arg isa Tuple && arg[1] == :state) || return same
    (added(code, "$key --> $(arg[2])"), (:move, length(r.moves) + 1), false)
  elseif tool == :start && kind == :state
    (added(code, "[*] --> $key"), (:move, length(r.moves) + 1), false)
  elseif tool == :stop && kind == :state
    (added(code, "$key --> [*]"), (:move, length(r.moves) + 1), false)
  elseif tool == :note && kind == :state
    (added(code, "note right of $key : Note"), (:note, length(r.notes) + 1), true)
  elseif tool == :turn && kind == :move
    n = r.move_at[key]
    m = match(MOVE, lines[n])
    (relined(code, Dict(n => [strip(m[2]) * " --> " * strip(m[1]) * (m[3] === nothing ? "" : " : " * m[3])])), (kind, key), false)
  elseif tool == :delete && kind == :move
    n = r.move_at[key]
    less = relined(code, Dict(n => String[]))
    # A state that only this arrow named stays, on a line of its own
    left = read_states(less).named
    lone = [s.id for s in (r.states[r.moves[key][1]], r.states[r.moves[key][2]]) if !(s.kind in (:start, :stop)) && !haskey(left, s.id)]
    (isempty(lone) ? less : relined(code, Dict(n => unique(lone))), nothing, false)
  elseif tool == :delete && kind == :state
    (without_state(code, r, key), nothing, false)
  elseif tool == :delete && kind == :note
    (relined(code, Dict(n => String[] for n in r.note_at[key] if haskey(lines, n))), nothing, false)
  elseif tool == :way
    arg isa AbstractString || return same
    r.turned != 0 && return (relined(code, Dict(r.turned => ["direction " * arg])), same[2], false)
    (added(code, "direction " * arg, after=statements(code)[1][1][1]), same[2], false)
  else
    same
  end
end

"How the parts of a state diagram are changed. See `EDITORS` in main.jl."
const state_edits = (said=state_said, reword=state_reword, tools=state_tools, use=state_use)

export state, state_edits
