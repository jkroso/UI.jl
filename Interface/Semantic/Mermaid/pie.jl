# A pie chart: a circle cut into slices, one for each number.
#
#     pie showData title Pets in the street
#       "Dogs" : 12
#       "Cats" : 7
#       "Fish" : 3
#
# Each line is a name in quotes, a colon and a number. A slice is as big a part
# of the pie as its number is of them all, and it shows that part as a
# percentage. The names are in a list beside the pie, with the numbers too if
# the first line has `showData`.

@use "./picture"...

const FIRST = r"^pie\b\s*(showData\b)?\s*(?:title\s+(.*))?$"

"""
What the code of a pie chart says: its title, whether it shows its numbers,
and its slices, each a name and a number. `at` is the line of the code that
each slice is on. `titled` is the line that gives the title, or 0 when the
top of the code gives it, or none does, and `shown` is the line that says to
show the numbers, or 0.
"""
read_pie(code::AbstractString) = begin
  lines, title = statements(code)
  first_line = match(FIRST, lines[1][2])
  first_line === nothing && throw(Problem(lines[1][1], "The first line is `pie`, then `showData` and `title` with a title if you want them"))
  numbers = first_line[1] !== nothing
  shown = numbers ? lines[1][1] : 0
  titled = 0
  first_line[2] === nothing || (title = plain(first_line[2]); titled = lines[1][1])
  slices, at = Tuple{String,Float64}[], Int[]
  for (n, line) in lines[2:end]
    if (m = match(r"^title\s+(.*)$", line)) !== nothing
      title, titled = plain(m[1]), n
    elseif line == "showData"
      numbers, shown = true, n
    elseif (m = match(r"^\"([^\"]*)\"\s*:\s*(-?[\d.]+)$", line)) !== nothing
      value = tryparse(Float64, m[2])
      (value === nothing || value < 0) && throw(Problem(n, "A slice needs a number that isn't less than 0"))
      push!(slices, (plain(m[1]), value))
      push!(at, n)
    elseif !occursin(r"^(accTitle|accDescr)\b", line)
      throw(Problem(n, "A slice is a name in quotes, a colon and a number"))
    end
  end
  (; title, numbers, slices, at, titled, shown, first=lines[1][1])
end

"A number as the code of a pie writes it: with no .0 when it's whole"
number(value::Real) = value == round(value) ? string(round(Int, value)) : string(value)

"The picture of the pie chart that `code` describes, with its text measured by `pen`"
pie(code::AbstractString, pen::Pen) = begin
  (; title, numbers, slices) = read_pie(code)
  u = pen.size
  total = sum(last, slices; init=0.0)
  total > 0 || return Picture(0.0, 0.0, Any[])

  items, parts, listed = Any[], Part[], Part[]
  small = 0.92u
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.5u
  r = 6.5u
  top = edge + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u)
  cx, cy = edge + r, top + r
  from = 0.0
  for (i, (_, value)) in enumerate(slices)
    value == 0 && continue
    to = from + 2pi * value / total
    push!(items, Slice(cx, cy, r, from, to, i))
    # The slice as a shape: the middle of the pie, then places along its edge
    steps = max(2, ceil(Int, (to - from) / 0.1))
    rim = [(cx + r * sin(from + (to - from) * k / steps), cy - r * cos(from + (to - from) * k / steps)) for k in 0:steps]
    push!(parts, Part(:slice, i, (cx - r, cy - r, 2r, 2r); path=to - from >= 2pi - 1e-6 ? rim : [(cx, cy); rim], shape=:area))
    # A slice that's big enough says how much of the pie it is
    if value / total >= 0.04
      middle = (from + to) / 2
      share = round(100value / total, digits=value / total < 0.1 ? 1 : 0)
      text = (share == round(share) ? string(round(Int, share)) : string(share)) * "%"
      push!(items, Words(text, cx + 0.66r * sin(middle), cy - 0.66r * cos(middle), :middle, small, false, false, :on_tone))
    end
    from = to
  end
  # The list of names: a square in the colour of each slice, then its name
  names = [label(pen, numbers ? "$name  ($(value == round(value) ? round(Int, value) : value))" : name, size=small) for (name, value) in slices]
  step = 1.7u
  list_top = cy - step * length(names) / 2
  left = cx + r + 2u
  for (i, l) in enumerate(names)
    y = list_top + step * (i - 0.5)
    push!(items, Shape(:rect, left, y - 0.45u, 0.9u, 0.9u; fill=i, line=nothing))
    write_from!(items, l, left + 1.5u, y)
    # A slice's words are its name in the list. A click on the name selects the slice too.
    push!(listed, labelled(:slice, i, (left, y - step / 2, 1.5u + l.w, step), l, left + 1.5u + l.w / 2, y))
  end
  parts = [Part(p.kind, p.key, p.box; p.path, p.shape, listed[p.key].words, listed[p.key].room) for p in parts]
  wide_list = maximum(l -> l.w, names; init=0.0) + 1.5u
  w = max(left + wide_list + edge, heading.w + 2edge)
  h = max(cy + r, list_top + step * length(names)) + edge
  isempty(heading.lines) || write!(items, heading, w / 2, edge + heading.h / 2)
  isempty(heading.lines) || push!(listed, labelled(:title, 1, (w / 2 - heading.w / 2, edge, heading.w, heading.h), heading, w / 2, edge + heading.h / 2))
  Picture(w, h, items, [parts; listed])
end

# --- changing a pie chart ---------------------------------------------------------
#
# The parts of a pie chart that can be selected are its slices, each a :slice
# with its number among the slices, and its title, which is the :title 1. The
# words of a slice are its name, a colon and its number, like `Dogs: 12`.

"The words that a part of the pie chart `code` shows, as you type them"
pie_said(code, kind::Symbol, key) = begin
  p = read_pie(code)
  kind == :slice ? p.slices[key][1] * ": " * number(p.slices[key][2]) : kind == :title ? p.title : nothing
end

"The first line of a pie chart, with or without the word that shows its numbers and with the title `title`, or with none"
top_line(numbers::Bool, title) = "pie" * (numbers ? " showData" : "") * (title === nothing || isempty(title) ? "" : " title " * title)

"The pie chart `code` with the title `title`, or with no title when that's empty"
retitled(code, title::AbstractString) = begin
  p = read_pie(code)
  title = String(strip(replace(title, '\n' => " ")))
  p.titled == p.first && return relined(code, Dict(p.first => [top_line(p.shown == p.first, title)]))
  p.titled != 0 && return relined(code, Dict(p.titled => isempty(title) ? String[] : ["title " * title]))
  # The top of the code gives the title, or nothing does. A title on a line of its own is used before that one.
  isempty(title) ? code : added(code, "title " * title, after=p.first)
end

"The pie chart `code` with `text` as the words of one of its parts"
pie_reword(code, kind::Symbol, key, text) = begin
  p = read_pie(code)
  if kind == :slice
    name, value = p.slices[key]
    # A number after a colon, at the end, is the slice's number. Without one, it keeps its number.
    m = match(r"^(.*?)\s*:\s*(\d+(?:\.\d+)?|\.\d+)\s*$", text)
    name, value = m === nothing ? (strip(text), number(value)) : (strip(m[1]), m[2])
    isempty(name) && return code
    relined(code, Dict(p.at[key] => ["\"" * replace(name, '"' => "'", '\n' => " ") * "\" : " * value]))
  elseif kind == :title
    retitled(code, text)
  else
    code
  end
end

"What you can do to the pie chart `code` while the part `key` of the kind `kind` is selected, or with `kind` :none while nothing is"
pie_tools(code, kind::Symbol, key) = begin
  p = read_pie(code)
  add = Tool(:add, "plus-circle", "Add a slice")
  kind == :slice ? [add, Tool(:delete, "trash3", "Take the slice away  ⌫")] :
  kind == :title ? [Tool(:delete, "trash3", "Take the title away  ⌫")] :
  [add, (isempty(p.title) ? [Tool(:title, "type", "Give the pie a title")] : Tool[])...,
   Tool(:numbers, "123", p.numbers ? "Hide the numbers in the list" : "Show the numbers in the list")]
end

"""
Use a tool on the pie chart `code`. Returns the new code, the part that's
selected after it, and whether the words of that part are typed next.
"""
pie_use(code, tool::Symbol, kind::Symbol, key, arg) = begin
  p = read_pie(code)
  same = (code, kind == :none ? nothing : (kind, key), false)
  if tool == :add
    # A new slice is as big as the others are on average
    value = isempty(p.slices) ? 1.0 : round(sum(last, p.slices) / length(p.slices), digits=1)
    line = "\"New slice\" : " * number(max(value, 1.0))
    (added(code, line, after=isempty(p.at) ? nothing : p.at[end]), (:slice, length(p.slices) + 1), true)
  elseif tool == :delete && kind == :slice
    (relined(code, Dict(p.at[key] => String[])), nothing, false)
  elseif tool == :delete && kind == :title
    (retitled(code, ""), nothing, false)
  elseif tool == :title
    (retitled(code, "Title"), (:title, 1), true)
  elseif tool == :numbers
    p.shown == 0 && return (relined(code, Dict(p.first => [replace(strip(split(code, '\n')[p.first]), r"^pie\b" => "pie showData")])), same[2], false)
    p.shown != p.first && return (relined(code, Dict(p.shown => String[])), same[2], false)
    (relined(code, Dict(p.first => [replace(strip(split(code, '\n')[p.first]), r"^pie\s+showData\b" => "pie")])), same[2], false)
  else
    same
  end
end

"How the parts of a pie chart are changed. See `EDITORS` in main.jl."
const pie_edits = (said=pie_said, reword=pie_reword, tools=pie_tools, use=pie_use)

export pie, pie_edits
