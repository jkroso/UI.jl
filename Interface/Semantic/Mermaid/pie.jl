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

"The picture of the pie chart that `code` describes, with its text measured by `pen`"
pie(code::AbstractString, pen::Pen) = begin
  lines, title = statements(code)
  u = pen.size
  first_line = match(r"^pie\b\s*(showData\b)?\s*(?:title\s+(.*))?$", lines[1][2])
  first_line === nothing && throw(Problem(lines[1][1], "The first line is `pie`, then `showData` and `title` with a title if you want them"))
  numbers = first_line[1] !== nothing
  first_line[2] === nothing || (title = plain(first_line[2]))
  slices = Tuple{String,Float64}[]
  for (n, line) in lines[2:end]
    if (m = match(r"^title\s+(.*)$", line)) !== nothing
      title = plain(m[1])
    elseif line == "showData"
      numbers = true
    elseif (m = match(r"^\"([^\"]*)\"\s*:\s*(-?[\d.]+)$", line)) !== nothing
      value = tryparse(Float64, m[2])
      (value === nothing || value < 0) && throw(Problem(n, "A slice needs a number that isn't less than 0"))
      push!(slices, (plain(m[1]), value))
    elseif !occursin(r"^(accTitle|accDescr)\b", line)
      throw(Problem(n, "A slice is a name in quotes, a colon and a number"))
    end
  end
  total = sum(last, slices; init=0.0)
  total > 0 || return Picture(0.0, 0.0, Any[])

  items = Any[]
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
  end
  wide_list = maximum(l -> l.w, names; init=0.0) + 1.5u
  w = max(left + wide_list + edge, heading.w + 2edge)
  h = max(cy + r, list_top + step * length(names)) + edge
  isempty(heading.lines) || write!(items, heading, w / 2, edge + heading.h / 2)
  Picture(w, h, items)
end

export pie
