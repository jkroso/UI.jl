# An entity relationship diagram: the things that a database keeps, what it
# knows about each, and how many of one thing go with another.
#
#     erDiagram
#       CUSTOMER ||--o{ ORDER : places
#       ORDER ||--|{ LINE-ITEM : contains
#       CUSTOMER {
#         int id PK
#         string name
#         string email UK "Where the bill goes"
#       }
#
# An entity is a box with its name at the top. Each line in its { } is a row
# of the box: a type, a name, then `PK`, `FK` or `UK` for a key, then a comment
# in quotes. `p[Person]` shows the entity `p` with the name Person.
#
# A line between two entities has a sign at each end that says how many there
# are at that end, and `--` or, for a dashed line, `..` between them. A sign
# is two characters, and the outer one is the most that there can be: `||` is
# exactly one, `|o` or `o|` is none or one, `}|` or `|{` is one or more, and
# `}o` or `o{` is none or more. Each is drawn in the crow's-foot way: a bar
# for one, a ring for none, and three toes for many. The words that Mermaid
# has for the signs are read too, like `only one to zero or more`. The text
# after the : goes on the line.
#
# `direction LR` makes the diagram go across. `style`, `classDef` and `class`
# give boxes their own colours. The box of a `subgraph` isn't drawn: what's in
# it is drawn as if it weren't in one.

@use "./picture"...
@use "./graph" Box Link arrange!

"What a database knows about an entity: its type, its name, its keys and a comment"
const Attribute = NTuple{4,String}

"A box of the diagram: a thing that the database keeps, with a row for each thing that it knows about it"
mutable struct Entity
  id::String
  name::String                 # the name that it shows
  rows::Vector{Attribute}
  classes::Vector{String}
  style::Dict{String,String}
end

"A line between two entities, with how many there are at each end"
struct Relationship
  from::String
  to::String
  left::Symbol                 # how many there are at each end: :one, :zero_or_one, :one_or_more or :zero_or_more
  right::Symbol
  dotted::Bool
  text::String
end

# How many there are at one end of a line, by the sign or the words that say it
const HOW_MANY = Dict("||" => :one, "only one" => :one, "1" => :one,
                      "|o" => :zero_or_one, "o|" => :zero_or_one, "one or zero" => :zero_or_one, "zero or one" => :zero_or_one,
                      "}|" => :one_or_more, "|{" => :one_or_more, "one or more" => :one_or_more, "one or many" => :one_or_more,
                      "many(1)" => :one_or_more, "1+" => :one_or_more,
                      "}o" => :zero_or_more, "o{" => :zero_or_more, "zero or more" => :zero_or_more, "zero or many" => :zero_or_more,
                      "many(0)" => :zero_or_more, "0+" => :zero_or_more)
const ENTITY_NAME = raw"(\"[^\"]+\"|[\p{L}\p{N}_][\p{L}\p{N}_-]*?)"
const TAGS = raw"(?::::([\w-]+(?:,[\w-]+)*))?"
const SIGN = raw"(\|o|\|\||\}o|\}\||o\||o\{|\|\{|one or zero|zero or one|one or more|one or many|many\(1\)|1\+|zero or more|zero or many|many\(0\)|0\+|only one|1)"
const RELATIONSHIP = Regex("^" * ENTITY_NAME * TAGS * raw"\s*" * SIGN * raw"\s*(--|\.\.|optionally to|to)\s*" * SIGN * raw"\s*" *
                           replace(ENTITY_NAME, "*?)" => "*)") * TAGS * raw"\s*(?::\s*(.*))?$")
const ENTITY = Regex("^" * replace(ENTITY_NAME, "*?)" => "*)") * raw"(?:\[([^\]]*)\])?" * TAGS * raw"\s*(\{)?\s*(\})?$")
const ATTRIBUTE = r"^(\S+)\s+(\S+?)(?:\s+((?:PK|FK|UK)(?:\s*,\s*(?:PK|FK|UK))*))?(?:\s+\"([^\"]*)\")?$"

"What the code of an entity relationship diagram says: its entities, the lines between them, the styles, which way it goes and its title"
read_entities(code::AbstractString) = begin
  lines, title = statements(code)
  entities, named = Entity[], Dict{String,Int}()
  relationships = Relationship[]
  styles_of = Dict{String,Dict{String,String}}()
  dir = :TB
  open = 0   # the entity whose { } is being read
  entity!(name, tags=nothing) = begin
    id = String(strip(name, '"'))
    i = get!(named, id) do
      push!(entities, Entity(id, plain(id), Attribute[], String[], Dict{String,String}()))
      length(entities)
    end
    tags === nothing || append!(entities[i].classes, String.(split(tags, ',')))
    i
  end
  for (n, line) in lines[2:end]
    if open != 0
      if line == "}"
        open = 0
      elseif (m = match(ATTRIBUTE, line)) !== nothing
        # A * before a name is another way to say that it's the key
        keys = something(m[3], startswith(m[2], '*') ? "PK" : "")
        push!(entities[open].rows, (String(m[1]), String(lstrip(m[2], '*')), String(replace(keys, r"\s*,\s*" => ", ")), plain(something(m[4], ""))))
      else
        throw(Problem(n, "A row of an entity is a type and a name, like `string name`"))
      end
    elseif (m = match(r"^direction\s+(\w+)$", line)) !== nothing
      dir = get(Dict("TB" => :TB, "TD" => :TB, "BT" => :BT, "LR" => :LR, "RL" => :RL), uppercase(m[1]), :TB)
    elseif (m = match(r"^classDef\s+(\S+)\s+(.*)$", line)) !== nothing
      foreach(name -> styles_of[String(name)] = styles(m[2]), split(m[1], ','))
    elseif (m = match(r"^class\s+(\S+)\s+(\S+)$", line)) !== nothing
      foreach(id -> append!(entities[entity!(id)].classes, String.(split(m[2], ','))), split(m[1], ','))
    elseif (m = match(r"^style\s+(\S+)\s+(.*)$", line)) !== nothing
      foreach(id -> merge!(entities[entity!(id)].style, styles(m[2])), split(m[1], ','))
    elseif occursin(r"^(subgraph\b|end$|accTitle\b|accDescr\b|click\b)", line)
      # Not drawn
    elseif (m = match(RELATIONSHIP, line)) !== nothing
      a, b = entity!(m[1], m[2]), entity!(m[6], m[7])
      push!(relationships, Relationship(entities[a].id, entities[b].id, HOW_MANY[m[3]], HOW_MANY[m[5]], m[4] in ("..", "optionally to"),
                                        plain(something(m[8], ""))))
    elseif (m = match(ENTITY, line)) !== nothing
      i = entity!(m[1], m[3])
      m[2] === nothing || (entities[i].name = plain(m[2]))
      m[4] !== nothing && m[5] === nothing && (open = i)
    else
      throw(Problem(n, "\"$(first(line, 30))\" isn't an entity or a line between two entities"))
    end
  end
  open == 0 || throw(Problem(0, "The { of the entity $(entities[open].id) is never closed"))
  (; entities, named, relationships, styles_of, dir, title)
end

"""
Put in `items` what the end of a line between two entities has, to say how
many there are at that end. The line meets its entity at `at`, and goes away
from it along `way`, which is one long. `u` is the size of the diagram's text.
"""
foot!(items, at::Point, way, many::Symbol, u; colour=:link, thick=0.09u) = begin
  # A place that's `along` from the entity on the line, and `side` to one side of it
  spot(along, side) = (at[1] + way[1] * along - way[2] * side, at[2] + way[2] * along + way[1] * side)
  half = 0.42u
  bar(along) = push!(items, Stroke([spot(along, -half), spot(along, half)]; colour, thick))
  ring(along) = (r = 0.3u; c = spot(along, 0.0); push!(items, Shape(:circle, c[1] - r, c[2] - r, 2r, 2r; fill=:surface, line=colour, thick)))
  if many in (:one_or_more, :zero_or_more)
    # Three toes: the line itself, and one to each side of where it meets the entity
    foreach(side -> push!(items, Stroke([spot(0.95u, 0.0), spot(0.0, side)]; colour, thick)), (-half, half))
    many == :one_or_more ? bar(1.25u) : ring(1.4u)
  else
    bar(0.5u)
    many == :one ? bar(0.9u) : ring(1.3u)
  end
  items
end

"The way that a line through `path` goes as it leaves its first point, one long"
leaves(path::Vector{Point}) = begin
  for q in path[2:end]
    d = hypot(q[1] - path[1][1], q[2] - path[1][2])
    d > 1e-6 && return ((q[1] - path[1][1]) / d, (q[2] - path[1][2]) / d)
  end
  (1.0, 0.0)
end

"""
The line through `path`, the points of a curved Stroke, made to go straight
for `long` as it leaves each end, so that what the end has sits on the line.
"""
straight_ends(path::Vector{Point}, long) = begin
  length(path) < 4 && return path
  # Where a straight piece from `a` towards `c` ends: no further than `c`
  lead(a, c) = (d = hypot(c[1] - a[1], c[2] - a[2]); d < 1e-6 ? a : between(a, c, min(long, d) / d))
  between(p, q, t) = (p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t)
  a, b = lead(path[1], path[2]), lead(path[end], path[end-1])
  # After its straight piece the line goes on the same way, and turns as gently as it did before
  on(from, p, c) = (from[1] + 0.6 * (c[1] - p[1]), from[2] + 0.6 * (c[2] - p[2]))
  [path[1], between(path[1], a, 1 / 3), between(path[1], a, 2 / 3), a, on(a, path[1], path[2]), path[3:end-2]...,
   on(b, path[end], path[end-1]), b, between(b, path[end], 1 / 3), between(b, path[end], 2 / 3), path[end]]
end

"The picture of the entity relationship diagram that `code` describes, with its text measured by `pen`"
er(code::AbstractString, pen::Pen) = begin
  (; entities, named, relationships, styles_of, dir, title) = read_entities(code)
  u = pen.size
  isempty(entities) && return Picture(0.0, 0.0, Any[])

  small = 0.92u
  step = leading(pen, small)
  gap = 0.9u   # between two columns of an entity's rows
  boxes, links = Box[], Link[]
  parts = map(entities) do e
    name = label(pen, e.name, bold=true)
    # Each column is as wide as its widest words: the types, the names, the keys and the comments
    columns = [maximum(r -> wide(pen, r[k], size=small, bold=k == 3, italic=k == 4), e.rows; init=0.0) for k in 1:4]
    rows_wide = sum(columns) + gap * (count(>(0), columns) - 1)
    head = name.h + 0.8u
    held = isempty(e.rows) ? 0.0 : length(e.rows) * step + 0.6u
    push!(boxes, Box(max(name.w, rows_wide) + 1.6u, head + held))
    (; name, columns, head)
  end
  texts = Label[]
  for r in relationships
    l = label(pen, r.text, most=13u, size=small)
    push!(texts, l)
    push!(links, Link(named[r.from], named[r.to]; lw=isempty(l.lines) ? 0.0 : l.w + 0.8u, lh=isempty(l.lines) ? 0.0 : l.h + 0.3u))
  end
  w, h = arrange!(boxes, links; dir, nodesep=3u, ranksep=4.4u, pad=1.1u)

  items = Any[]
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.5u
  # A line from an entity to itself goes round at the entity's right, past the diagram's own edge
  right = maximum(p -> p[1], (p for l in links for p in l.path); init=w)
  w = max(w, right + 0.3u)
  ox = edge + max(0.0, (heading.w - w) / 2)
  oy = edge + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u)
  isempty(heading.lines) || write!(items, heading, ox + w / 2, edge + heading.h / 2)
  moved(p) = (p[1] + ox, p[2] + oy)
  for (i, r) in enumerate(relationships)
    l = links[i]
    isempty(l.path) && continue
    path = straight_ends(moved.(l.path), 1.9u)
    around = isempty(texts[i].lines) ? NTuple{4,Float64}[] : [(ox + l.lx - l.lw / 2 + 0.15u, oy + l.ly - l.lh / 2, l.lw - 0.3u, l.lh)]
    push!(items, Stroke(path; curved=true, thick=0.09u, dash=r.dotted ? :dashed : :solid, around))
    write!(items, texts[i], ox + l.lx, oy + l.ly)
    foot!(items, path[1], leaves(path), r.left, u)
    foot!(items, path[end], leaves(reverse(path)), r.right, u)
  end
  for (i, e) in enumerate(entities)
    b, p = boxes[i], parts[i]
    x, y = ox + b.x - b.w / 2, oy + b.y - b.h / 2
    style = Dict{String,String}()
    foreach(tag -> merge!(style, get(styles_of, tag, Dict{String,String}())), e.classes)
    fill, line, thick, dash, text = look(merge!(style, e.style), u)
    push!(items, Shape(:rect, x, y, b.w, b.h; fill, line, thick, dash))
    write!(items, p.name, ox + b.x, y + p.head / 2, colour=text)
    isempty(e.rows) && continue
    push!(items, Stroke([(x, y + p.head), (x + b.w, y + p.head)]; colour=line, thick))
    # A box with its own colour has all its words in the colour that shows on it
    quiet = text == :text ? :dim : text
    for (k, row) in enumerate(e.rows)
      middle = y + p.head + 0.3u + step * (k - 0.5)
      at = x + 0.8u
      for (c, words) in enumerate(row)
        p.columns[c] > 0 || continue
        isempty(words) || push!(items, Words(words, at, middle, :left, small, c == 3, c == 4, c == 2 ? text : quiet))
        at += p.columns[c] + gap
      end
    end
  end
  Picture(max(w, heading.w) + 2edge, oy + h + edge, items)
end

export er
