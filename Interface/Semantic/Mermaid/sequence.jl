# A sequence diagram: who says what to whom, in order, down the page.
#
#     sequenceDiagram
#       participant A as Alice
#       actor B as Bob
#       A->>B: Hello Bob
#       activate B
#       B-->>A: Hello Alice
#       deactivate B
#       Note over A,B: They know each other now
#
# Each participant has a box at the top and the bottom, with a line between
# them. `actor` draws a person in place of a box. A message is an arrow from
# one line to another: ->> has an arrow, -> has none, -x has a cross and -) is
# open, and two dashes make the line dotted. A + after the arrow starts a bar
# on the line of whoever gets the message, to show that they're busy, and a -
# ends the sender's bar. `loop`, `alt` with `else`, `opt`, `par` with `and`,
# `critical` with `option`, and `break` put a frame around the messages as far
# as `end`. `rect` colours what's behind them. `autonumber` numbers the messages.

@use "./picture"...

const ARROWS = [("<<-->>", :dotted, :arrow, true), ("<<->>", :solid, :arrow, true), ("-->>", :dotted, :arrow, false),
                ("->>", :solid, :arrow, false), ("--x", :dotted, :cross, false), ("-x", :solid, :cross, false),
                ("--)", :dotted, :open, false), ("-)", :solid, :open, false), ("-->", :dotted, :none, false),
                ("->", :solid, :none, false)]
const MESSAGE = Regex("^(.+?)\\s*(" * join((replace(a, ")" => "\\)") for (a, _, _, _) in ARROWS), "|") * ")\\s*([+-])?\\s*(.+?)\\s*(?::\\s*(.*))?\$")

"A frame around some messages while it's open: a loop, an alt and so on"
mutable struct Frame
  frame::Symbol
  text::String
  top::Float64
  tint::Any
  parts::Vector{Tuple{Float64,String}}   # where each `else` is, and its text
  lo::Float64                            # how far across what's in it goes
  hi::Float64
end
Frame(f::NamedTuple) = Frame(f.frame, f.text, f.top, f.tint, f.parts, Inf, -Inf)

const PERSON = r"^(participant|actor)\s+(.+?)(?:\s+as\s+(.+))?$"
const NOTE = r"^note\s+(left of|right of|over)\s+([^:]+):\s*(.*)$"i

"""
What the code of a sequence diagram says: who's in it, in `ids`, with the
name that each shows and whether they're drawn as a person, and its `events`
in order: each message, note and frame, with the `line` of the code that
it's on. `seen` is the line that first names each participant, and `said` is
the line that says `participant` or `actor` for the ones that have one.
"""
read_sequence(code::AbstractString) = begin
  lines, title = statements(code)
  ids, names, people = String[], Dict{String,String}(), Set{String}()
  groups = Any[]    # the boxes around some participants: a title, a colour and who's in it
  events = Any[]
  seen, said = Dict{String,Int}(), Dict{String,Int}()
  numbered = false
  grouping = false
  nesting, deepest = Symbol[], 0
  at = 0   # the line that's being read
  actor!(id) = begin
    id = String(strip(id))
    if !(id in ids)
      push!(ids, id)
      seen[id] = at
      grouping && push!(groups[end].members, id)
    end
    id
  end
  for (n, line) in lines[2:end]
    at = n
    line = replace(line, r"^create\s+" => "")
    if (m = match(PERSON, line)) !== nothing
      id = actor!(m[2])
      said[id] = n
      m[3] === nothing || (names[id] = plain(m[3]))
      m[1] == "actor" && push!(people, id)
    elseif (m = match(r"^title:?\s+(.*)$", line)) !== nothing
      title = plain(m[1])
    elseif startswith(line, "autonumber")
      numbered = true
    elseif (m = match(r"^(activate|deactivate)\s+(.+)$", line)) !== nothing
      push!(events, (kind=Symbol(m[1]), who=actor!(m[2])))
    elseif (m = match(NOTE, line)) !== nothing
      who = actor!.(split(m[2], ','))
      push!(events, (kind=:note, side=lowercase(m[1]), who=who, text=plain(m[3]), line=n))
    elseif (m = match(r"^box\b\s*(.*)$", line)) !== nothing
      first_word = match(r"^(rgba?\([^)]*\)|\S+)\s*(.*)$", m[1])
      tint = first_word === nothing ? nothing : paint(first_word[1])
      named = first_word !== nothing && (tint !== nothing || lowercase(first_word[1]) == "transparent")
      push!(groups, (title=plain(named ? first_word[2] : m[1]), tint=tint, members=String[]))
      grouping = true
    elseif (m = match(r"^(loop|alt|opt|par|critical|break|rect)\b\s*(.*)$", line)) !== nothing
      push!(nesting, Symbol(m[1]))
      deepest = max(deepest, count(!=(:rect), nesting))
      push!(events, (kind=:open, frame=Symbol(m[1]), text=String(m[2])))
    elseif (m = match(r"^(else|and|option)\b\s*(.*)$", line)) !== nothing
      isempty(nesting) && throw(Problem(n, "This `$(m[1])` is in no frame"))
      push!(events, (kind=:divide, text=plain(m[2])))
    elseif line == "end"
      if grouping
        grouping = false
      else
        isempty(nesting) && throw(Problem(n, "This `end` closes nothing"))
        pop!(nesting)
        push!(events, (kind=:close,))
      end
    elseif occursin(r"^(destroy|links?|properties|accTitle|accDescr)\b", line)
      # Not drawn
    elseif (m = match(MESSAGE, line)) !== nothing
      _, dash, head, both = ARROWS[findfirst(a -> a[1] == m[2], ARROWS)]
      from, to = actor!(m[1]), actor!(m[4])
      push!(events, (kind=:message, from=from, to=to, text=plain(something(m[5], "")), dash=dash, head=head, both=both, mark=something(m[3], ""), line=n))
    else
      throw(Problem(n, "\"$(first(line, 30))\" isn't a message, a note or a frame"))
    end
  end
  (; ids, names, people, groups, events, numbered, deepest, title, seen, said)
end

"The events of a sequence diagram that are of the kind `kind`, in order: its messages, or its notes"
those(events, kind::Symbol) = [ev for ev in events if ev.kind == kind]

"The picture of the sequence diagram that `code` describes, with its text measured by `pen`"
sequence(code::AbstractString, pen::Pen) = begin
  (; ids, names, people, groups, events, numbered, deepest, title) = read_sequence(code)
  u = pen.size
  isempty(ids) && return Picture(0.0, 0.0, Any[])
  k = length(ids)
  index = Dict(id => i for (i, id) in enumerate(ids))
  parts = Part[]
  messages, noted = 0, 0   # how many messages and notes have been drawn

  # --- across: a column for each participant, far enough apart for what goes between them
  small = 0.92u
  names_laid = [label(pen, get(names, id, id), most=10u) for id in ids]
  person = 3.3u   # how tall the drawing of a person is
  boxw = [id in people ? max(l.w, 2.6u) : max(l.w + 2u, 6u) for (id, l) in zip(ids, names_laid)]
  headh = maximum(id in people ? person + 0.3u + l.h : l.h + 1.4u for (id, l) in zip(ids, names_laid))
  gaps = [(boxw[i] + boxw[i+1]) / 2 + 2u for i in 1:k-1]
  left, right = boxw[1] / 2, boxw[k] / 2
  spans = Tuple{Int,Int,Float64}[]
  beside!(i, w) = i < k ? push!(spans, (i, i + 1, w + boxw[i+1] / 2)) : (right = max(right, w))   # room at the right of line i
  before!(i, w) = i > 1 ? push!(spans, (i - 1, i, w + boxw[i-1] / 2)) : (left = max(left, w))
  laid = map(events) do ev
    ev.kind == :message ? label(pen, ev.text, most=18u, size=small) : ev.kind == :note ? label(pen, ev.text, most=14u, size=small) : nothing
  end
  for (ev, l) in zip(events, laid)
    if ev.kind == :message
      i, j = minmax(index[ev.from], index[ev.to])
      i == j ? beside!(i, max(l.w + 1.4u, 3.4u)) : push!(spans, (i, j, l.w + 2.4u))
    elseif ev.kind == :note
      i, j = extrema(index[w] for w in ev.who)
      w = l.w + 1.4u
      ev.side == "right of" ? beside!(j, w + 0.9u) : ev.side == "left of" ? before!(i, w + 0.9u) :
      i == j ? (beside!(i, w / 2 + 0.4u); before!(i, w / 2 + 0.4u)) : push!(spans, (i, j, w - 2.4u))
    end
  end
  for (i, j, w) in sort(spans, by=s -> s[2] - s[1])
    short = w - sum(gaps[i:j-1])
    short > 0 && (gaps[i:j-1] .+= short / (j - i))
  end
  # A frame goes a little past the lines that it's around, and so does a box around participants
  edge = 0.5u + 1.3u * deepest + (isempty(groups) ? 0.0 : 0.8u)
  x = zeros(k)
  x[1] = left + edge
  for i in 2:k
    x[i] = x[i-1] + gaps[i-1]
  end
  wide = x[k] + right + edge

  # --- down: each message, note and frame in turn
  behind, frames, arrows, notes, bars = Any[], Any[], Any[], Any[], Any[]
  heading = label(pen, title, bold=true, size=1.1u)
  group_room = any(g -> !isempty(g.title), groups) ? 1.5u : isempty(groups) ? 0.0 : 0.6u
  top = 0.4u + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u) + group_room
  y = top + headh + 1.1u
  busy = [Float64[] for _ in 1:k]    # where each bar that's open on a line started
  barw, step = 0.7u, 0.35u
  open = Any[]                       # the frames that are open: what they are, where they start, and how far across they go
  last_line = y
  number = 0
  reach!(a, b) = foreach(f -> (f.lo = min(f.lo, a); f.hi = max(f.hi, b)), open)
  shut!(i, at) = begin
    isempty(busy[i]) && return
    from = pop!(busy[i])
    push!(bars, Shape(:plain, x[i] - barw / 2 + step * length(busy[i]), from, barw, max(at - from, 0.6u); fill=:bar, line=:link, thick=0.07u))
  end
  for (ev, l) in zip(events, laid)
    if ev.kind == :message
      i, j = index[ev.from], index[ev.to]
      ev.mark == "+" && push!(busy[j], 0.0)   # its place is set once the arrow's is known
      if i == j
        # A message to yourself: a loop at the right of the line, with its text over it
        words = (x[i] + 0.9u + max(l.w, 3u) / 2, y + max(l.h, 1.35small) / 2)
        isempty(l.lines) || (write!(arrows, l, x[i] + 0.9u + l.w / 2, y + l.h / 2); y += l.h + 0.4u)
        from = x[i] + (isempty(busy[i]) ? 0.0 : barw / 2 + step * (length(busy[i]) - 1))
        push!(arrows, Stroke([(from, y), (from + 3u, y), (from + 3u, y + 1.5u), (from, y + 1.5u)]; curved=true, thick=0.09u, dash=ev.dash, to=ev.head, tip=0.75u))
        push!(parts, labelled(:message, messages += 1, (x[i] + 0.9u, words[2] - l.h / 2, l.w, l.h), l, words...;
                              path=flat([(from, y), (from + 3u, y), (from + 3u, y + 1.5u), (from, y + 1.5u)])))
        reach!(x[i], x[i] + max(3.4u, l.w + 1.4u))
        line = y
        y += 1.5u
      else
        way = j > i ? 1 : -1
        # Its words are over the arrow, and that's where they're typed when it has none yet
        words = ((x[i] + x[j]) / 2, isempty(l.lines) ? y - 0.9u : y + l.h / 2)
        isempty(l.lines) || (write!(arrows, l, (x[i] + x[j]) / 2, y + l.h / 2); y += l.h + 0.35u)
        # The arrow goes from the edge of a bar to the edge of a bar
        inset(p, towards) = isempty(busy[p]) ? 0.0 : towards > 0 ? barw / 2 + step * (length(busy[p]) - 1) : barw / 2
        from, to = x[i] + way * inset(i, 1), x[j] - way * inset(j, -1)
        push!(arrows, Stroke([(from, y), (to, y)]; thick=0.09u, dash=ev.dash, from=ev.both ? ev.head : :none, to=ev.head, tip=0.75u))
        push!(parts, labelled(:message, messages += 1, (words[1] - l.w / 2, words[2] - l.h / 2, l.w, l.h), l, words...; path=[(from, y), (to, y)]))
        reach!(min(x[i], x[j]), max(x[i], x[j]))
        line = y
      end
      if numbered
        number += 1
        at = i == j ? x[i] : x[i] + (j > i ? 1 : -1) * (isempty(busy[i]) ? 0.0 : barw / 2)
        push!(arrows, Shape(:circle, at - 0.7u, line - 0.7u, 1.4u, 1.4u; fill=:accent, line=nothing))
        push!(arrows, Words(string(number), at, line, :middle, 0.8u, true, false, :on_accent))
      end
      ev.mark == "+" && (busy[j][end] = line)
      ev.mark == "-" && shut!(i, line)
      last_line = line
      y = (i == j ? y : line) + 1.2u
    elseif ev.kind == :activate
      push!(busy[index[ev.who]], last_line)
    elseif ev.kind == :deactivate
      shut!(index[ev.who], last_line)
    elseif ev.kind == :note
      i, j = extrema(index[w] for w in ev.who)
      w, h = l.w + 1.4u, l.h + 0.8u
      at = ev.side == "right of" ? x[j] + 0.9u : ev.side == "left of" ? x[i] - 0.9u - w :
           i == j ? x[i] - w / 2 : (w = max(w, x[j] - x[i] + 2.4u); (x[i] + x[j]) / 2 - w / 2)
      push!(notes, Shape(:rect, at, y, w, h; fill=:note, line=:note_edge, thick=0.07u))
      write!(notes, l, at + w / 2, y + h / 2)
      push!(parts, labelled(:note, noted += 1, (at, y, w, h), l, at + w / 2, y + h / 2))
      reach!(at, at + w)
      y += h + 1.0u
    elseif ev.kind == :open
      tint = ev.frame == :rect ? something(paint(ev.text), :group) : nothing
      push!(open, (frame=ev.frame, text=ev.frame == :rect ? "" : plain(ev.text), top=y - 0.3u, tint=tint, parts=Tuple{Float64,String}[]) |> Frame)
      y += ev.frame == :rect ? 0.5u : 1.9u
    elseif ev.kind == :divide
      push!(open[end].parts, (y - 0.3u, ev.text))
      y += 1.6u
    elseif ev.kind == :close
      f = pop!(open)
      f.lo > f.hi && ((f.lo, f.hi) = (x[1], x[k]))
      pad = 1.3u
      a, b, bottom = f.lo - pad, f.hi + pad, y - 0.4u
      if f.frame == :rect
        push!(behind, Shape(:rect, a, f.top, b - a, bottom - f.top; fill=f.tint, line=nothing))
      else
        push!(frames, Shape(:rect, a, f.top, b - a, bottom - f.top; fill=nothing, line=:dim, thick=0.07u))
        # The kind of frame is in a tab at its corner, and what it's for comes after the tab
        tab = label(pen, string(f.frame), bold=true, size=0.85u)
        push!(frames, Shape(:plain, a, f.top, tab.w + 1.1u, 1.4u; fill=:bar, line=:dim, thick=0.07u))
        write!(frames, tab, a + (tab.w + 1.1u) / 2, f.top + 0.7u)
        isempty(f.text) || write_from!(frames, label(pen, "[" * f.text * "]", size=0.88u), a + tab.w + 1.7u, f.top + 0.7u, colour=:dim)
        for (at, text) in f.parts
          push!(frames, Stroke([(a, at), (b, at)]; colour=:dim, thick=0.07u, dash=:dashed))
          isempty(text) || write_from!(frames, label(pen, "[" * text * "]", size=0.88u), a + 0.6u, at + 0.75u, colour=:dim)
        end
      end
      reach!(a, b)
      y += 0.8u
    end
  end
  foreach(i -> while !isempty(busy[i]); shut!(i, y - 0.6u) end, 1:k)
  y += 0.2u

  items = Any[]
  isempty(heading.lines) || write!(items, heading, wide / 2, 0.4u + heading.h / 2)
  for g in groups
    isempty(g.members) && continue
    i, j = extrema(index[m] for m in g.members)
    a, b = x[i] - boxw[i] / 2 - 0.7u, x[j] + boxw[j] / 2 + 0.7u
    push!(items, Shape(:rect, a, top - group_room, b - a, y + headh + group_room + 0.5u - top; fill=something(g.tint, :group), line=:line, thick=0.07u))
    isempty(g.title) || write!(items, label(pen, g.title, size=small, bold=true), (a + b) / 2, top - group_room + 0.8u, colour=g.tint === nothing ? :text : on(g.tint))
  end
  append!(items, behind)
  for i in 1:k
    push!(items, Stroke([(x[i], top + headh), (x[i], y)]; colour=:line, thick=0.09u))
  end
  append!(items, bars); append!(items, frames); append!(items, arrows); append!(items, notes)
  for at in (top, y), i in 1:k
    l = names_laid[i]
    if ids[i] in people
      # A person: a head, a body, two arms and two legs, with the name under them
      cx, r = x[i], 0.55u
      figure = at == top ? at + headh - person - 0.3u - l.h : at
      push!(items, Shape(:circle, cx - r, figure, 2r, 2r; fill=:node, line=:link, thick=0.09u))
      body, hips = figure + 2r, figure + 2r + 1.1u
      for (a, b) in (((cx, body), (cx, hips)), ((cx - 0.9u, body + 0.45u), (cx + 0.9u, body + 0.45u)),
                     ((cx, hips), (cx - 0.75u, figure + person)), ((cx, hips), (cx + 0.75u, figure + person)))
        push!(items, Stroke([a, b]; thick=0.09u))
      end
      write!(items, l, cx, figure + person + 0.3u + l.h / 2)
      push!(parts, labelled(:person, ids[i], (cx - boxw[i] / 2, figure, boxw[i], person + 0.3u + l.h), l, cx, figure + person + 0.3u + l.h / 2))
    else
      h = l.h + 1.4u
      # The box at the top stands on its line, and the one at the bottom hangs from it
      box_top = at == top ? at + headh - h : at
      push!(items, Shape(:rect, x[i] - boxw[i] / 2, box_top, boxw[i], h))
      write!(items, l, x[i], box_top + h / 2)
      push!(parts, labelled(:person, ids[i], (x[i] - boxw[i] / 2, box_top, boxw[i], h), l, x[i], box_top + h / 2))
    end
  end
  # A click chooses someone or a note before a message
  Picture(max(wide, heading.w + 0.8u), y + headh + 0.4u + (isempty(groups) ? 0.0 : 0.6u), items, sort(parts, by=p -> p.kind == :message ? 2 : 1))
end

# --- changing a sequence diagram --------------------------------------------------
#
# The parts of a sequence diagram that can be selected are who's in it, each a
# :person with their name in the code, its messages, each a :message with its
# number among the messages, and its notes, each a :note with its number.

const ARROW_NAMES = ["Arrow" => "->>", "Dotted arrow" => "-->>", "Line with no arrow" => "->", "Dotted line" => "-->",
                     "Line with a cross" => "-x", "Open arrow" => "-)"]
const DRAWN_AS = ["A box" => "participant", "A person" => "actor"]

"A name for someone new that nobody in the diagram has: a capital letter, or P with a number once the letters are used"
fresh_person(ids) = begin
  for c in 'A':'Z'
    string(c) in ids || return string(c)
  end
  n = 1
  while "P$n" in ids
    n += 1
  end
  "P$n"
end

"The line `n` of `code`, as the diagram reads it: without the white space round it"
said_line(code, n::Int) = String(strip(split(code, '\n')[n]))

"The words that a part of the sequence diagram `code` shows, as you type them"
sequence_said(code, kind::Symbol, key) = begin
  r = read_sequence(code)
  kind == :person ? typed(get(r.names, key, key)) :
  kind == :message ? typed(those(r.events, :message)[key].text) :
  kind == :note ? typed(those(r.events, :note)[key].text) : nothing
end

"""
`code` with the line that says how `id` is drawn and what name they show. Someone
that only a message names gets that line before the first line that names
them, so they keep their place among the others.
"""
declared(code, r, id, word, name) = begin
  line = word * " " * id * (name == id || isempty(name) ? "" : " as " * name)
  haskey(r.said, id) && return relined(code, Dict(r.said[id] => [line]))
  n = r.seen[id]
  relined(code, Dict(n => [line, said_line(code, n)]))
end

"The sequence diagram `code` with `text` as the words of one of its parts"
sequence_reword(code, kind::Symbol, key, text) = begin
  r = read_sequence(code)
  text = String(strip(replace(text, '\n' => "<br>")))
  if kind == :person
    isempty(text) ? code : declared(code, r, key, key in r.people ? "actor" : "participant", text)
  elseif kind == :message
    n = those(r.events, :message)[key].line
    line = said_line(code, n)
    made = startswith(line, r"create\s+") ? "create " : ""
    m = match(MESSAGE, replace(line, r"^create\s+" => ""))
    relined(code, Dict(n => [made * m[1] * m[2] * something(m[3], "") * m[4] * (isempty(text) ? "" : ": " * text)]))
  elseif kind == :note
    isempty(text) && return code
    n = those(r.events, :note)[key].line
    m = match(NOTE, said_line(code, n))
    relined(code, Dict(n => ["Note " * lowercase(m[1]) * " " * strip(m[2]) * ": " * text]))
  else
    code
  end
end

"What you can do to the sequence diagram `code` while the part `key` of the kind `kind` is selected, or with `kind` :none while nothing is"
sequence_tools(code, kind::Symbol, key) = begin
  up, down = Tool(:up, "arrow-up", "Move it up, before what comes before it"), Tool(:down, "arrow-down", "Move it down, after what comes after it")
  kind == :person ? [Tool(:message, "chat-right-text", "Add a message from them: click who it goes to", target=true),
                     Tool(:note, "sticky", "Add a note beside them"),
                     Tool(:drawn, "person", "Draw them as a box or as a person", choices=DRAWN_AS),
                     Tool(:delete, "trash3", "Take them away, with their messages  ⌫")] :
  kind == :message ? [Tool(:look, "arrow-right", "Change how the arrow looks", choices=ARROW_NAMES),
                      Tool(:turn, "arrow-left-right", "Turn the message round"), up, down,
                      Tool(:delete, "trash3", "Take the message away  ⌫")] :
  kind == :note ? [up, down, Tool(:delete, "trash3", "Take the note away  ⌫")] :
  [Tool(:add, "person-plus", "Add someone")]
end

"`code` without `id`: the line that names them, their messages, and the notes that are only theirs"
without_person(code, r, id) = begin
  gone = Dict{Int,Vector{String}}()
  haskey(r.said, id) && (gone[r.said[id]] = String[])
  for ev in r.events
    if ev.kind == :message
      id in (ev.from, ev.to) && (gone[ev.line] = String[])
    elseif ev.kind == :note && id in ev.who
      left = filter(!=(id), ev.who)
      m = match(NOTE, said_line(code, ev.line))
      gone[ev.line] = isempty(left) ? String[] : ["Note " * lowercase(m[1]) * " " * join(left, ",") * ": " * m[3]]
    end
  end
  for (n, line) in statements(code)[1]
    m = match(r"^(?:activate|deactivate|destroy)\s+(.+)$", line)
    m !== nothing && strip(m[1]) == id && (gone[n] = String[])
  end
  less = relined(code, gone)
  # Someone that only a message to or from them named stays
  left = read_sequence(less).ids
  lone = [who for who in r.ids if who != id && !(who in left)]
  isempty(lone) ? less : added(less, ("participant " * who for who in lone)...)
end

"`code` without the message or the note on line `n`. Someone that only that line named stays, with a line of their own in its place."
without_event(code, r, n::Int) = begin
  left = read_sequence(relined(code, Dict(n => String[]))).ids
  relined(code, Dict(n => String["participant " * who for who in r.ids if !(who in left)]))
end

"""
Use a tool on the sequence diagram `code`. `arg` is the choice, or the part
that was clicked, for a tool that needs one. Returns the new code, the part
that's selected after it, and whether the words of that part are typed next.
"""
sequence_use(code, tool::Symbol, kind::Symbol, key, arg) = begin
  r = read_sequence(code)
  same = (code, kind == :none ? nothing : (kind, key), false)
  messages, notes = those(r.events, :message), those(r.events, :note)
  if tool == :add
    id = fresh_person(r.ids)
    (added(code, "participant $id as Someone"), (:person, id), true)
  elseif tool == :message && kind == :person
    (arg isa Tuple && arg[1] == :person) || return same
    (added(code, "$key->>$(arg[2]): Message"), (:message, length(messages) + 1), true)
  elseif tool == :note && kind == :person
    (added(code, "Note right of $key: Note"), (:note, length(notes) + 1), true)
  elseif tool == :drawn && kind == :person
    arg in ("participant", "actor") || return same
    (declared(code, r, key, arg, get(r.names, key, key)), (kind, key), false)
  elseif tool == :delete && kind == :person
    (without_person(code, r, key), nothing, false)
  elseif kind in (:message, :note) && tool in (:up, :down, :delete, :look, :turn)
    n = (kind == :message ? messages : notes)[key].line
    tool == :delete && return (without_event(code, r, n), nothing, false)
    if tool in (:up, :down)
      # It changes places with the line of code beside it. Past the line that opens or closes a frame, it's in or out of the frame.
      said = [k for (k, _) in statements(code)[1]]
      i = findfirst(==(n), said) + (tool == :up ? -1 : 1)
      (2 <= i <= length(said)) || return same
      new = swapped(code, n, said[i])
      events = those(read_sequence(new).events, kind)
      at = findfirst(ev -> ev.line == said[i], events)
      return (new, at === nothing ? nothing : (kind, at), false)
    end
    kind == :message || return same
    line = said_line(code, n)
    made = startswith(line, r"create\s+") ? "create " : ""
    m = match(MESSAGE, replace(line, r"^create\s+" => ""))
    words = m[5] === nothing ? "" : ": " * m[5]
    tool == :turn && return (relined(code, Dict(n => [made * m[4] * m[2] * something(m[3], "") * m[1] * words])), (kind, key), false)
    arg isa AbstractString || return same
    (relined(code, Dict(n => [made * m[1] * arg * something(m[3], "") * m[4] * words])), (kind, key), false)
  else
    same
  end
end

"How the parts of a sequence diagram are changed. See `EDITORS` in main.jl."
const sequence_edits = (said=sequence_said, reword=sequence_reword, tools=sequence_tools, use=sequence_use)

export sequence, sequence_edits
