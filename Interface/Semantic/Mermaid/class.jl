# A class diagram: the classes of a program, what each one holds and does, and
# how they're related.
#
#     classDiagram
#       class Animal {
#         +String name
#         +eat() void
#       }
#       Animal <|-- Dog
#       Dog "1" *-- "4" Leg : has
#
# A class is a box in three parts: its name, what it holds, and what it does,
# which is each line that has a ( in it. A line between two classes is -- or,
# with dots, `..`. Each end of it can have a sign: <| or |> for a triangle
# (the class at the triangle is the parent), * for a full diamond (it's made
# of the other), o for an empty diamond (it has the other) and < or > for an
# arrow. Text in quotes beside a class says how many there are, and text after
# a : goes on the line. `<<interface>>` in a class goes over its name.

@use "./picture"...
@use "./graph" Box Link arrange! across

mutable struct Class
  id::String
  name::String
  mark::String              # what goes over its name, like «interface»
  holds::Vector{String}
  does::Vector{String}
  inside::Int               # the namespace that it's in, or 0
  classes::Vector{String}
  style::Dict{String,String}
end

struct Relation
  from::String
  to::String
  tail::Symbol
  head::Symbol
  dotted::Bool
  text::String
  many_from::String
  many_to::String
end

const NAME = raw"(`[^`]+`|[\w.~-]+?)"
const RELATION = Regex("^" * NAME * raw"\s*(\"[^\"]*\")?\s*(<\||\*|(?<=\s)o|<)?(--|\.\.)(\|>|\*|o(?=\s|\")|>)?\s*(\"[^\"]*\")?\s*" * replace(NAME, "+?)" => "+)") * raw"\s*(?::\s*(.*))?$")
const ENDS = Dict("<|" => :triangle, "|>" => :triangle, "*" => :diamond, "o" => :hollow, "<" => :open, ">" => :open)

"The name of a class as it's shown: Dog~T~ is Dog<T>"
shown(name) = replace(strip(name, '`'), r"~([^~]*)~" => s"<\1>")

const CLASS = r"^class\s+([^\s{]+)\s*(?:\[\"([^\"]*)\"\])?\s*(\{)?\s*(\})?$"
const OWN = r"^([^\s:]+)\s*:\s*(.*)$"

"""
What the code of a class diagram says: its classes, the lines between them
and its notes. The rest says where each is in the code. `members` has, for
each class by its name, the line of the code that each line of the class is
on: what it holds first, then what it does, as they're drawn. `said` is the
line that says `class` for each class that has one, and `closes` is the line
with the } of each class that has a {. `seen` is the line that first names
each class. `relation_at` and `note_at` are the lines of the lines between
classes and of the notes, and `turned` is the line that says which way the
diagram goes, or 0.
"""
read_classes(code::AbstractString) = begin
  lines, title = statements(code)
  classes, named = Class[], Dict{String,Int}()
  relations = Relation[]
  notes = Tuple{String,String}[]   # the class that each note is for, or "", and its text
  spaces = String[]                # the namespaces
  styles_of = Dict{String,Dict{String,String}}()
  held, done = Dict{String,Vector{Int}}(), Dict{String,Vector{Int}}()
  said, closes, seen = Dict{String,Int}(), Dict{String,Int}(), Dict{String,Int}()
  relation_at, note_at, turned = Int[], Int[], 0
  at = 0   # the line that's being read
  dir = :TB
  open_class, open_space = 0, 0
  class!(name) = begin
    name = String(strip(name))
    tags = String[]
    if (m = match(r"^(.*?):::([\w-]+)$", name)) !== nothing
      name, tags = String(m[1]), [String(m[2])]
    end
    id = String(replace(strip(name, '`'), r"~.*$" => ""))
    i = get!(named, id) do
      push!(classes, Class(id, shown(name), "", String[], String[], open_space, String[], Dict{String,String}()))
      seen[id] = at
      length(classes)
    end
    occursin('~', name) && (classes[i].name = shown(name))
    append!(classes[i].classes, tags)
    i
  end
  member!(i, text) = begin
    text = strip(text)
    isempty(text) && return
    if (m = match(r"^<<(.+)>>$", text)) !== nothing
      classes[i].mark = "«" * m[1] * "»"
    else
      # A * at the end says that it's abstract and a \$ that it's static. They aren't drawn.
      text = replace(shown(text), r"[*$]$" => "")
      push!(occursin('(', text) ? classes[i].does : classes[i].holds, String(text))
      push!(get!(Vector{Int}, occursin('(', text) ? done : held, classes[i].id), at)
    end
  end
  for (n, line) in lines[2:end]
    at = n
    if open_class != 0
      line == "}" ? (closes[classes[open_class].id] = n; open_class = 0) : member!(open_class, line)
    elseif (m = match(r"^direction\s+(\w+)$", line)) !== nothing
      dir = get(Dict("TB" => :TB, "TD" => :TB, "BT" => :BT, "LR" => :LR, "RL" => :RL), uppercase(m[1]), :TB)
      turned = n
    elseif (m = match(r"^namespace\s+(\S+)\s*\{$", line)) !== nothing
      push!(spaces, m[1])
      open_space = length(spaces)
    elseif line == "}"
      open_space == 0 && throw(Problem(n, "This } closes nothing"))
      open_space = 0
    elseif (m = match(CLASS, line)) !== nothing
      i = class!(m[1])
      said[classes[i].id] = n
      m[2] === nothing || (classes[i].name = plain(m[2]))
      m[3] !== nothing && m[4] === nothing && (open_class = i)
    elseif (m = match(r"^<<(.+)>>\s*(\S+)$", line)) !== nothing
      classes[class!(m[2])].mark = "«" * m[1] * "»"
    elseif (m = match(r"^note\s+for\s+(\S+)\s+\"(.*)\"$", line)) !== nothing
      push!(notes, (classes[class!(m[1])].id, plain(m[2])))
      push!(note_at, n)
    elseif (m = match(r"^note\s+\"(.*)\"$", line)) !== nothing
      push!(notes, ("", plain(m[1])))
      push!(note_at, n)
    elseif (m = match(r"^classDef\s+(\S+)\s+(.*)$", line)) !== nothing
      foreach(name -> styles_of[String(name)] = styles(m[2]), split(m[1], ','))
    elseif (m = match(r"^cssClass\s+\"([^\"]*)\"\s+([\w-]+)$", line)) !== nothing
      foreach(name -> push!(classes[class!(name)].classes, String(m[2])), split(m[1], ','))
    elseif (m = match(r"^style\s+(\S+)\s+(.*)$", line)) !== nothing
      merge!(classes[class!(m[1])].style, styles(m[2]))
    elseif occursin(r"^(click|link|callback|accTitle|accDescr)\b", line)
      # Not drawn
    elseif (m = match(RELATION, line)) !== nothing
      a, b = class!(m[1]), class!(m[7])
      unquote(s) = s === nothing ? "" : String(strip(s, '"'))
      push!(relations, Relation(classes[a].id, classes[b].id, get(ENDS, something(m[3], ""), :none), get(ENDS, something(m[5], ""), :none),
                                m[4] == "..", plain(something(m[8], "")), unquote(m[2]), unquote(m[6])))
      push!(relation_at, n)
    elseif (m = match(OWN, line)) !== nothing
      member!(class!(m[1]), m[2])
    else
      throw(Problem(n, "\"$(first(line, 30))\" isn't a class or a line between two classes"))
    end
  end
  open_class == 0 || throw(Problem(0, "The { of the class $(classes[open_class].id) is never closed"))
  members = Dict(c.id => [get(held, c.id, Int[]); get(done, c.id, Int[])] for c in classes)
  (; classes, named, relations, notes, spaces, styles_of, dir, title, members, said, closes, seen, relation_at, note_at, turned)
end

"The picture of the class diagram that `code` describes, with its text measured by `pen`"
class(code::AbstractString, pen::Pen) = begin
  (; classes, named, relations, notes, spaces, styles_of, dir, title) = read_classes(code)
  u = pen.size
  isempty(classes) && return Picture(0.0, 0.0, Any[])

  small = 0.92u
  step = leading(pen, small)
  boxes, links = Box[], Link[]
  # A namespace is a box that classes are in
  space_labels = [label(pen, s, size=small, bold=true) for s in spaces]
  for l in space_labels
    push!(boxes, Box(l.w + 2u, l.h + 2.4u; dir, head=l.h + 0.2u, least=l.w + 2u))
  end
  first_class = length(boxes)
  parts = map(classes) do c
    name = label(pen, c.name, bold=true)
    mark = label(pen, c.mark, size=0.85u, italic=true)
    wide_text = maximum(l -> wide(pen, l, size=small), [c.holds; c.does]; init=0.0)
    w = max(name.w, mark.w, wide_text) + 1.6u
    head = name.h + mark.h + 0.8u
    # A class with nothing in it is its name alone. Any other has both of its lower parts, and an empty one is thin.
    bare = isempty(c.holds) && isempty(c.does)
    held = bare ? 0.0 : max(length(c.holds) * step + 0.6u, 0.7u)
    done = bare ? 0.0 : max(length(c.does) * step + 0.6u, 0.7u)
    push!(boxes, Box(max(w, 5u), head + held + done; inside=c.inside))
    (name=name, mark=mark, head=head, held=held, done=done)
  end
  box_of(id) = first_class + named[id]
  texts = Label[]
  for r in relations
    l = label(pen, r.text, most=13u, size=small)
    push!(texts, l)
    push!(links, Link(box_of(r.from), box_of(r.to); lw=isempty(l.lines) ? 0.0 : l.w + 0.8u, lh=isempty(l.lines) ? 0.0 : l.h + 0.3u))
  end
  note_boxes = Tuple{Int,Label,Int}[]
  for (id, text) in notes
    l = label(pen, text, most=14u, size=small)
    push!(boxes, Box(l.w + 1.4u, l.h + 0.8u))
    push!(note_boxes, (length(boxes), l, isempty(id) ? 0 : length(links) + 1))
    isempty(id) || push!(links, Link(length(boxes), box_of(id)))
  end
  w, h = arrange!(boxes, links; dir, nodesep=2.6u, ranksep=3.4u, pad=1.1u)

  items, chosen = Any[], Part[]
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.4u
  ox = edge + max(0.0, (heading.w - w) / 2)
  oy = edge + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u)
  isempty(heading.lines) || write!(items, heading, ox + w / 2, edge + heading.h / 2)
  for (i, l) in enumerate(space_labels)
    b = boxes[i]
    push!(items, Shape(:round, ox + b.x - b.w / 2, oy + b.y - b.h / 2, b.w, b.h; fill=:group, line=:line))
    write!(items, l, ox + b.x, oy + b.y - b.h / 2 + 0.45u + l.h / 2, colour=:dim)
  end
  moved(p) = (p[1] + ox, p[2] + oy)
  for (i, r) in enumerate(relations)
    l = links[i]
    isempty(l.path) && continue
    path = moved.(l.path)
    around = isempty(texts[i].lines) ? NTuple{4,Float64}[] : [(ox + l.lx - l.lw / 2 + 0.15u, oy + l.ly - l.lh / 2, l.lw - 0.3u, l.lh)]
    push!(items, Stroke(path; curved=true, thick=0.09u, dash=r.dotted ? :dashed : :solid, from=r.tail, to=r.head, tip=0.85u, around))
    write!(items, texts[i], ox + l.lx, oy + l.ly)
    # A line's words are in its label, or at its middle when it has none
    way = flat(path)
    words = isempty(texts[i].lines) ? halfway(way) : (ox + l.lx, oy + l.ly)
    room = isempty(texts[i].lines) ? (words[1], words[2], 0.0, 0.0) : (ox + l.lx - l.lw / 2, oy + l.ly - l.lh / 2, l.lw, l.lh)
    push!(chosen, labelled(:relation, i, room, texts[i], words...; path=way))
    # How many there are at each end goes beside the line, a little way from the class
    for (text, at, next) in ((r.many_from, path[1], path[2]), (r.many_to, path[end], path[end-1]))
      isempty(text) && continue
      d = hypot(next[1] - at[1], next[2] - at[2])
      d < 1e-6 && continue
      dx, dy = (next[1] - at[1]) / d, (next[2] - at[2]) / d
      many = label(pen, text, size=0.85u)
      write!(items, many, at[1] + 1.4u * dx - (0.5u + many.w / 2) * dy, at[2] + 1.4u * dy + (0.5u + many.h / 2) * dx, colour=:dim)
    end
  end
  for (k, (at, l, link)) in enumerate(note_boxes)
    b = boxes[at]
    if link != 0 && !isempty(links[link].path)
      push!(items, Stroke(moved.(links[link].path); curved=true, colour=:note_edge, thick=0.08u, dash=:dotted))
    end
    push!(items, Shape(:rect, ox + b.x - b.w / 2, oy + b.y - b.h / 2, b.w, b.h; fill=:note, line=:note_edge, thick=0.07u))
    write!(items, l, ox + b.x, oy + b.y)
    push!(chosen, labelled(:note, k, (ox + b.x - b.w / 2, oy + b.y - b.h / 2, b.w, b.h), l, ox + b.x, oy + b.y))
  end
  for (i, c) in enumerate(classes)
    b, p = boxes[first_class+i], parts[i]
    x, y = ox + b.x - b.w / 2, oy + b.y - b.h / 2
    style = Dict{String,String}()
    foreach(tag -> merge!(style, get(styles_of, tag, Dict{String,String}())), c.classes)
    fill, line, thick, dash, text = look(merge!(style, c.style), u)
    push!(items, Shape(:rect, x, y, b.w, b.h; fill, line, thick, dash))
    isempty(p.mark.lines) || write!(items, p.mark, ox + b.x, y + 0.4u + p.mark.h / 2, colour=text)
    write!(items, p.name, ox + b.x, y + 0.4u + p.mark.h + p.name.h / 2, colour=text)
    at = y + p.head
    row_number = 0   # the place of a line among the lines of the class
    for (rows, tall) in ((c.holds, p.held), (c.does, p.done))
      tall == 0 && continue
      push!(items, Stroke([(x, at), (x + b.w, at)]; colour=line, thick))
      for (k, row) in enumerate(rows)
        middle = at + 0.3u + step * (k - 0.5)
        push!(items, Words(row, x + 0.8u, middle, :left, small, false, false, text))
        wide_row = wide(pen, row, size=small)
        push!(chosen, Part(:member, (c.id, row_number += 1), (x, middle - step / 2, b.w, step); words=(x + 0.8u + wide_row / 2, middle), room=(wide_row, step)))
      end
      at += tall
    end
    # The words of a class are its name, at its top
    push!(chosen, labelled(:class, c.id, (x, y, b.w, b.h), p.name, ox + b.x, y + 0.4u + p.mark.h + p.name.h / 2))
  end
  # A click chooses a line of a class before the class, and a class or a note before a line between two classes
  order(p::Part) = p.kind == :member ? 1 : p.kind == :relation ? 3 : 2
  Picture(max(w, heading.w) + 2edge, oy + h + edge, items, sort(chosen, by=order))
end

# --- changing a class diagram -----------------------------------------------------
#
# The parts of a class diagram that can be selected are its classes, each a
# :class with its name, the lines of a class, each a :member with the name of
# its class and its place among the lines of that class, the lines between
# two classes, each a :relation with its number among them, and its notes,
# each a :note with its number.

# What a line between two classes can say, with the signs that the code has at its two ends and whether it's dotted
const RELATION_NAMES = ["Is a kind of" => ("", "|>", false), "Is made of" => ("*", "", false), "Has" => ("o", "", false),
                        "Uses" => ("", ">", false), "Is joined to" => ("", "", false), "Depends on" => ("", ">", true),
                        "Does what it says" => ("", "|>", true)]
const CLASS_WAYS = ["Down" => "TB", "Across" => "LR", "Up" => "BT", "Across, from the right" => "RL"]

"A name for a new class that no class has: Class with a number"
fresh_class(named) = begin
  n = 1
  while haskey(named, "Class$n")
    n += 1
  end
  "Class$n"
end

"The line `n` of `code`, as the diagram reads it: without the white space round it"
class_line(code, n::Int) = String(strip(split(code, '\n')[n]))

"The name of a class as a line of the code writes it, without what it's a class of and the style after it"
class_name(text) = String(replace(strip(replace(strip(text), r":::[\w-]+$" => ""), '`'), r"~.*$" => ""))

"The words that a part of the class diagram `code` shows, as you type them"
class_said(code, kind::Symbol, key) = begin
  r = read_classes(code)
  if kind == :class
    typed(r.classes[r.named[key]].name)
  elseif kind == :member
    c = r.classes[r.named[key[1]]]
    typed([c.holds; c.does][key[2]])
  elseif kind == :relation
    typed(r.relations[key].text)
  elseif kind == :note
    typed(r.notes[key][2])
  end
end

"The line of the code that draws a line between two classes, with other signs at its ends, or the same ones and other words"
relation_line(m; left=something(m[3], ""), dash=m[4], right=something(m[5], ""), text=m[8]) = begin
  many(q) = q === nothing ? "" : " " * q
  m[1] * many(m[2]) * " " * left * dash * right * many(m[6]) * " " * m[7] * (text === nothing || isempty(text) ? "" : " : " * text)
end

"`code` with the name `new` for the class `old`, in each line that names the class"
renamed(code, r, old, new) = begin
  changed = Dict{Int,Vector{String}}()
  name = Regex("(?<![\\w.~-])\\Q" * old * "\\E(?![\\w.-])")
  inside = false
  for (n, line) in statements(code)[1][2:end]
    if inside
      line == "}" && (inside = false)
      continue
    end
    m = match(CLASS, line)
    m !== nothing && m[3] !== nothing && m[4] === nothing && (inside = true)
    # What comes after a colon is a line of a class or the words of a line, which the name isn't changed in
    head, tail = occursin(RELATION, line) || occursin(OWN, line) ? (m2 = match(r"^(.*?)(\s*:.*)?$", line); (m2[1], something(m2[2], ""))) : (line, "")
    occursin(name, head) && (changed[n] = [replace(head, name => new) * tail])
  end
  relined(code, changed)
end

"The class diagram `code` with `text` as the words of one of its parts"
class_reword(code, kind::Symbol, key, text) = begin
  r = read_classes(code)
  text = String(strip(replace(text, '\n' => " ")))
  if kind == :class
    isempty(text) && return code
    c = r.classes[r.named[key]]
    # A class that shows words that aren't its name keeps its name, and shows the new words
    n = get(r.said, key, 0)
    m = n == 0 ? nothing : match(CLASS, class_line(code, n))
    if m !== nothing && m[2] !== nothing
      return relined(code, Dict(n => [replace(class_line(code, n), r"\[\"[^\"]*\"\]" => "[\"" * replace(text, '"' => "'") * "\"]")]))
    end
    # A name is one word. Words with a space in them are shown by a class that keeps the name that it has.
    if occursin(r"^[\w.-]+$", text)
      haskey(r.named, text) && return code
      return (renamed(code, r, key, text), (:class, text))
    end
    shown_as = "[\"" * replace(text, '"' => "'") * "\"]"
    n == 0 && return added(code, "class " * key * shown_as, after=r.seen[key] - 1)
    relined(code, Dict(n => [replace(class_line(code, n), r"^class\s+[^\s{\[]+" => named -> named * shown_as)]))
  elseif kind == :member
    n = r.members[key[1]][key[2]]
    isempty(text) && return relined(code, Dict(n => String[]))
    # A line in the { } of its class is the words alone. Outside it, the name of the class and a colon come first.
    m = match(OWN, class_line(code, n))
    inside = haskey(r.closes, key[1]) && r.said[key[1]] < n < r.closes[key[1]]
    relined(code, Dict(n => [inside || m === nothing ? text : m[1] * " : " * text]))
  elseif kind == :relation
    n = r.relation_at[key]
    relined(code, Dict(n => [relation_line(match(RELATION, class_line(code, n)), text=text)]))
  elseif kind == :note
    isempty(text) && return code
    n = r.note_at[key]
    relined(code, Dict(n => [replace(class_line(code, n), r"\".*\"$" => "\"" * replace(text, '"' => "'") * "\"")]))
  else
    code
  end
end

"What you can do to the class diagram `code` while the part `key` of the kind `kind` is selected, or with `kind` :none while nothing is"
class_tools(code, kind::Symbol, key) =
  kind == :class ? [Tool(:line, "list-ul", "Add a line to the class: what it holds, or with ( ) what it does"),
                    Tool(:join, "bezier2", "Draw a line from this class: click the class that it goes to", target=true),
                    Tool(:add, "node-plus", "Add a class that's a kind of this one"),
                    Tool(:note, "sticky", "Add a note for the class"),
                    Tool(:delete, "trash3", "Take the class away  ⌫")] :
  kind == :member ? [Tool(:line, "list-ul", "Add a line under this one"), Tool(:delete, "trash3", "Take the line away  ⌫")] :
  kind == :relation ? [Tool(:look, "arrow-right", "Change what the line says about the two classes", choices=RELATION_NAMES),
                       Tool(:turn, "arrow-left-right", "Turn the line round"),
                       Tool(:delete, "trash3", "Take the line away  ⌫")] :
  kind == :note ? [Tool(:delete, "trash3", "Take the note away  ⌫")] :
  [Tool(:add, "plus-square", "Add a class"), Tool(:way, "signpost-split", "Change which way the diagram goes", choices=CLASS_WAYS)]

"`code` without the class `id`: the lines that say what's in it, the lines between it and other classes, and its notes"
without_class(code, r, id) = begin
  gone = Dict{Int,Vector{String}}()
  haskey(r.said, id) && foreach(n -> gone[n] = String[], r.said[id]:get(r.closes, id, r.said[id]))
  foreach(n -> gone[n] = String[], r.members[id])
  for (k, rel) in enumerate(r.relations)
    id in (rel.from, rel.to) && (gone[r.relation_at[k]] = String[])
  end
  for (k, note) in enumerate(r.notes)
    note[1] == id && (gone[r.note_at[k]] = String[])
  end
  for (n, line) in statements(code)[1]
    haskey(gone, n) && continue
    m = match(r"^(?:style|click|link|callback)\s+(\S+)", line)
    m !== nothing && class_name(m[1]) == id && (gone[n] = String[])
    m = match(r"^<<.+>>\s*(\S+)$", line)
    m !== nothing && class_name(m[1]) == id && (gone[n] = String[])
  end
  less = relined(code, gone)
  # A class that only a line to this one named stays
  left = read_classes(less).named
  lone = [c.id for c in r.classes if c.id != id && !haskey(left, c.id)]
  isempty(lone) ? less : added(less, ("class " * c for c in lone)...)
end

"`code` without the line between two classes that has the number `k`. A class that only that line named stays, on a line of its own."
without_relation(code, r, k::Int) = begin
  n = r.relation_at[k]
  left = read_classes(relined(code, Dict(n => String[]))).named
  lone = unique(String[id for id in (r.relations[k].from, r.relations[k].to) if !haskey(left, id)])
  relined(code, Dict(n => String["class " * id for id in lone]))
end

"""
Use a tool on the class diagram `code`. `arg` is the choice, or the part that
was clicked, for a tool that needs one. Returns the new code, the part that's
selected after it, and whether the words of that part are typed next.
"""
class_use(code, tool::Symbol, kind::Symbol, key, arg) = begin
  r = read_classes(code)
  same = (code, kind == :none ? nothing : (kind, key), false)
  if tool == :add
    id = fresh_class(r.named)
    # A class that's a kind of the selected one, or a class by itself
    kind == :class ? (added(code, "$key <|-- $id"), (:class, id), true) : (added(code, "class $id"), (:class, id), true)
  elseif tool == :line && kind in (:class, :member)
    id = kind == :class ? key : key[1]
    # The new line holds something, so it goes after the last thing that the class holds
    c = r.classes[r.named[id]]
    # Its place among the lines of the class: after the things that the class holds and that come before it in the code
    place(after) = (:member, (id, count(<=(after), r.members[id][1:length(c.holds)]) + 1))
    if haskey(r.closes, id)
      # In the { } of the class: after the line that's selected, or before the }
      after = kind == :member && r.said[id] < r.members[id][key[2]] < r.closes[id] ? r.members[id][key[2]] : r.closes[id] - 1
      lines = String.(split(code, '\n'))
      pad = after > r.said[id] ? indent(lines[after]) : indent(lines[r.said[id]]) * "  "
      new = join(vcat(lines[1:after], [pad * "+name"], lines[after+1:end]), '\n')
      return (new, place(after), true)
    end
    after = isempty(r.members[id]) ? get(r.said, id, r.seen[id]) : maximum(r.members[id])
    (added(code, "$id : +name", after=after), place(after), true)
  elseif tool == :join && kind == :class
    (arg isa Tuple && arg[1] == :class) || return same
    (added(code, "$key --> $(arg[2])"), (:relation, length(r.relations) + 1), false)
  elseif tool == :note && kind == :class
    (added(code, "note for $key \"Note\""), (:note, length(r.notes) + 1), true)
  elseif tool == :delete
    kind == :class ? (without_class(code, r, key), nothing, false) :
    kind == :member ? (relined(code, Dict(r.members[key[1]][key[2]] => String[])), nothing, false) :
    kind == :relation ? (without_relation(code, r, key), nothing, false) :
    kind == :note ? (relined(code, Dict(r.note_at[key] => String[])), nothing, false) : same
  elseif kind == :relation && tool in (:look, :turn)
    n = r.relation_at[key]
    m = match(RELATION, class_line(code, n))
    if tool == :turn
      # The two classes change places, and each end keeps its sign and its number
      flip(sign) = sign == "<|" ? "|>" : sign == "|>" ? "<|" : sign == "<" ? ">" : sign == ">" ? "<" : sign
      many(q) = q === nothing ? "" : " " * q
      line = m[7] * many(m[6]) * " " * flip(something(m[5], "")) * m[4] * flip(something(m[3], "")) * many(m[2]) * " " * m[1] *
             (m[8] === nothing || isempty(m[8]) ? "" : " : " * m[8])
      return (relined(code, Dict(n => [line])), (kind, key), false)
    end
    arg isa Tuple || return same
    (relined(code, Dict(n => [relation_line(m, left=arg[1], dash=arg[3] ? ".." : "--", right=arg[2])])), (kind, key), false)
  elseif tool == :way
    arg isa AbstractString || return same
    r.turned != 0 && return (relined(code, Dict(r.turned => ["direction " * arg])), same[2], false)
    (added(code, "direction " * arg, after=statements(code)[1][1][1]), same[2], false)
  else
    same
  end
end

"How the parts of a class diagram are changed. See `EDITORS` in main.jl."
const class_edits = (said=class_said, reword=class_reword, tools=class_tools, use=class_use)

export class, class_edits
