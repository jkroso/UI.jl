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

"The picture of the class diagram that `code` describes, with its text measured by `pen`"
class(code::AbstractString, pen::Pen) = begin
  lines, title = statements(code)
  u = pen.size
  classes, named = Class[], Dict{String,Int}()
  relations = Relation[]
  notes = Tuple{String,String}[]   # the class that each note is for, or "", and its text
  spaces = String[]                # the namespaces
  styles_of = Dict{String,Dict{String,String}}()
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
    end
  end
  for (n, line) in lines[2:end]
    if open_class != 0
      line == "}" ? (open_class = 0) : member!(open_class, line)
    elseif (m = match(r"^direction\s+(\w+)$", line)) !== nothing
      dir = get(Dict("TB" => :TB, "TD" => :TB, "BT" => :BT, "LR" => :LR, "RL" => :RL), uppercase(m[1]), :TB)
    elseif (m = match(r"^namespace\s+(\S+)\s*\{$", line)) !== nothing
      push!(spaces, m[1])
      open_space = length(spaces)
    elseif line == "}"
      open_space == 0 && throw(Problem(n, "This } closes nothing"))
      open_space = 0
    elseif (m = match(r"^class\s+([^\s{]+)\s*(?:\[\"([^\"]*)\"\])?\s*(\{)?\s*(\})?$", line)) !== nothing
      i = class!(m[1])
      m[2] === nothing || (classes[i].name = plain(m[2]))
      m[3] !== nothing && m[4] === nothing && (open_class = i)
    elseif (m = match(r"^<<(.+)>>\s*(\S+)$", line)) !== nothing
      classes[class!(m[2])].mark = "«" * m[1] * "»"
    elseif (m = match(r"^note\s+for\s+(\S+)\s+\"(.*)\"$", line)) !== nothing
      push!(notes, (classes[class!(m[1])].id, plain(m[2])))
    elseif (m = match(r"^note\s+\"(.*)\"$", line)) !== nothing
      push!(notes, ("", plain(m[1])))
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
    elseif (m = match(r"^([^\s:]+)\s*:\s*(.*)$", line)) !== nothing
      member!(class!(m[1]), m[2])
    else
      throw(Problem(n, "\"$(first(line, 30))\" isn't a class or a line between two classes"))
    end
  end
  open_class == 0 || throw(Problem(0, "The { of the class $(classes[open_class].id) is never closed"))
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

  items = Any[]
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
  for (at, l, link) in note_boxes
    b = boxes[at]
    if link != 0 && !isempty(links[link].path)
      push!(items, Stroke(moved.(links[link].path); curved=true, colour=:note_edge, thick=0.08u, dash=:dotted))
    end
    push!(items, Shape(:rect, ox + b.x - b.w / 2, oy + b.y - b.h / 2, b.w, b.h; fill=:note, line=:note_edge, thick=0.07u))
    write!(items, l, ox + b.x, oy + b.y)
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
    for (rows, tall) in ((c.holds, p.held), (c.does, p.done))
      tall == 0 && continue
      push!(items, Stroke([(x, at), (x + b.w, at)]; colour=line, thick))
      for (k, row) in enumerate(rows)
        push!(items, Words(row, x + 0.8u, at + 0.3u + step * (k - 0.5), :left, small, false, false, text))
      end
      at += tall
    end
  end
  Picture(max(w, heading.w) + 2edge, oy + h + edge, items)
end

export class
