# A mind map: one idea in the middle, and the ideas that belong to it around it.
#
#     mindmap
#       root((Kaydown))
#         Pages
#           Diagrams
#           Tables
#         Sharing
#           [A page of HTML]
#           (A printed page)
#
# The first line under `mindmap` is the idea in the middle. Each line after it
# is an idea that belongs to the nearest line above it that starts further
# left. An idea is its words alone, or its words in the signs of a shape:
# `[a box]`, `(a round box)`, `((a circle))`, `{{a hexagon}}`, `)a cloud(` and
# `))a bang((`. A name can come before the signs, as in `root((Kaydown))`. The
# name isn't shown. A cloud is drawn as a pill and a bang as a hexagon.
#
# The ideas that belong to the middle one go out to its right and to its left.
# Each of them has a colour of its own, and the ideas under it share that
# colour. A line that starts with `::icon(` or `:::` is read and not drawn.

@use "./picture"...

"An idea of a mind map"
mutable struct Idea
  text::String
  shape::Symbol            # :default for words alone, or :rect, :round, :circle, :hexagon, :stadium
  parent::Int              # the idea that it belongs to, or 0 for the one in the middle
  children::Vector{Int}
  depth::Int               # how many ideas are between it and the middle, with itself
  branch::Int              # which of the middle idea's own ideas it's under, or 0 for the middle
  line::Int                # the line of the code that it's on
end

# What can come before the signs of a shape: a name, which has none of the signs in it
const BEFORE = raw"^[^\(\[\{\)\}]*"
# The signs of each shape, with the shape that's drawn for it. The longer signs are tried first.
const SIGNS = [(Regex(BEFORE * raw"\(\((.*)\)\)$", "s"), :circle), (Regex(BEFORE * raw"\)\)(.*)\(\($", "s"), :hexagon),
               (Regex(BEFORE * raw"\)(.*)\($", "s"), :stadium), (Regex(BEFORE * raw"\{\{(.*)\}\}$", "s"), :hexagon),
               (Regex(BEFORE * raw"\[(.*)\]$", "s"), :rect), (Regex(BEFORE * raw"\((.*)\)$", "s"), :round)]

"The words and the shape that a line of a mind map gives an idea"
idea_of(text::AbstractString) = begin
  for (signs, shape) in SIGNS
    m = match(signs, text)
    m === nothing || return (plain(m[1]), shape)
  end
  (plain(text), :default)
end

"""
What the code of a mind map says: its ideas, with the one in the middle first,
and the title that the top of the code gave.
"""
read_ideas(code::AbstractString) = begin
  lines, title = statements(code)
  raw = split(code, '\n')
  ideas = Idea[]
  open = Tuple{Int,Int}[]   # the ideas that the next line can belong to, each with how far in its line starts
  k = 2
  while k <= length(lines)
    n, text = lines[k]
    k += 1
    (startswith(text, "::icon(") || startswith(text, ":::") || occursin(r"^(accTitle|accDescr)\b", text)) && continue
    # Words in "` `" can go on over more lines
    while count("\"`", text) > count("`\"", text) && k <= length(lines)
      text *= "\n" * lines[k][2]
      k += 1
    end
    far = length(indent(raw[n]))
    while !isempty(open) && open[end][1] >= far
      pop!(open)
    end
    isempty(open) && !isempty(ideas) && throw(Problem(n, "Only the first idea can start this far left. The others belong to it."))
    words, shape = idea_of(text)
    parent = isempty(open) ? 0 : open[end][2]
    push!(ideas, Idea(words, shape, parent, Int[], 0, 0, n))
    i = length(ideas)
    if parent != 0
      push!(ideas[parent].children, i)
      ideas[i].depth = ideas[parent].depth + 1
      ideas[i].branch = parent == 1 ? length(ideas[1].children) : ideas[parent].branch
    end
    push!(open, (far, i))
  end
  ideas, title
end

"How many of `tall`, from the first, go on the right of the middle so that the two sides are as near as can be to the same height"
right_side(tall::Vector{Float64}) = begin
  isempty(tall) && return 0
  total = sum(tall)
  argmin(k -> abs(2sum(tall[1:k]) - total) - 1e-9k, 1:length(tall))
end

"The picture of the mind map that `code` describes, with its text measured by `pen`"
mindmap(code::AbstractString, pen::Pen) = begin
  ideas, title = read_ideas(code)
  isempty(ideas) && return Picture(0.0, 0.0, Any[])
  u = pen.size
  n = length(ideas)
  small = 0.92u
  labels = [i.depth == 0 ? label(pen, i.text, most=14u, size=1.15u, bold=true) :
            i.depth == 1 ? label(pen, i.text, most=13u, bold=true) : label(pen, i.text, most=13u, size=small) for i in ideas]
  # Words alone are in a pill in the middle, in a round box beside the middle, and on a line further out
  shapes = [i.shape != :default ? i.shape : i.depth == 0 ? :stadium : i.depth == 1 ? :round : :default for i in ideas]
  sizes = map(1:n) do i
    l, shape = labels[i], shapes[i]
    h = max(l.h, leading(pen, l.size))
    shape == :circle ? (d = max(hypot(l.w, h) + 0.9u, 2.6u); (d, d)) :
    shape in (:hexagon, :stadium) ? (l.w + 1.4u + (h + 0.9u) / 2, h + 0.9u) :
    shape == :default ? (l.w + 0.8u, h + 0.5u) : (l.w + 1.6u, h + 0.9u)
  end
  gap, between, apart = 0.7u, 2.6u, 1.3u
  # How tall each idea is with all that's under it
  tall = zeros(n)
  for i in n:-1:1
    kids = ideas[i].children
    tall[i] = max(sizes[i][2], sum(tall[k] for k in kids; init=0.0) + gap * max(length(kids) - 1, 0))
  end
  x, y, side = zeros(n), zeros(n), ones(Int, n)
  # Put the idea `i` with its near edge at `edge` and all that's under it from `top` down, on the side `s` of the middle
  place!(i, edge, top, s) = begin
    w, h = sizes[i]
    x[i], side[i] = edge + s * w / 2, s
    kids = ideas[i].children
    at = top + (tall[i] - sum(tall[k] for k in kids; init=0.0) - gap * max(length(kids) - 1, 0)) / 2
    for k in kids
      place!(k, edge + s * (w + between), at, s)
      at += tall[k] + gap
    end
    y[i] = isempty(kids) ? top + tall[i] / 2 : clamp((y[kids[1]] + y[kids[end]]) / 2, top + h / 2, top + tall[i] - h / 2)
  end
  tops = ideas[1].children
  k = right_side(tall[tops])
  whole(list) = sum(tall[i] for i in list; init=0.0) + apart * max(length(list) - 1, 0)
  high = max(whole(tops[1:k]), whole(tops[k+1:end]), sizes[1][2])
  y[1] = high / 2
  for (list, s) in ((tops[1:k], 1), (tops[k+1:end], -1))
    at = (high - whole(list)) / 2
    for i in list
      place!(i, s * (sizes[1][1] / 2 + between), at, s)
      at += tall[i] + apart
    end
  end

  items = Any[]
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.5u
  lo, hi = minimum(x[i] - sizes[i][1] / 2 for i in 1:n), maximum(x[i] + sizes[i][1] / 2 for i in 1:n)
  ox = edge - lo + max(0.0, (heading.w - (hi - lo)) / 2)
  oy = edge + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u)
  w = max(hi - lo, heading.w) + 2edge
  isempty(heading.lines) || write!(items, heading, w / 2, edge + heading.h / 2)
  # An idea that's words on a line has its lines meet that line. Any other has them meet the middle of its side.
  joins(i) = oy + y[i] + (shapes[i] == :default ? sizes[i][2] / 2 : 0.0)
  for i in 2:n
    p, s = ideas[i].parent, side[i]
    a = (ox + x[p] + s * sizes[p][1] / 2, joins(p))
    b = (ox + x[i] - s * sizes[i][1] / 2, joins(i))
    mid = (a[1] + b[1]) / 2
    push!(items, Stroke([a, (mid, a[2]), (mid, b[2]), b]; curved=true, colour=ideas[i].branch, thick=ideas[i].depth == 1 ? 0.2u : 0.12u))
  end
  for (i, idea) in enumerate(ideas)
    (bw, bh), l, tone = sizes[i], labels[i], idea.branch
    left, top = ox + x[i] - bw / 2, oy + y[i] - bh / 2
    if shapes[i] == :default
      push!(items, Stroke([(left, top + bh), (left + bw, top + bh)]; colour=tone, thick=0.12u))
      write!(items, l, ox + x[i], oy + y[i])
    elseif idea.depth == 0
      push!(items, Shape(shapes[i], left, top, bw, bh; fill=:accent, line=nothing))
      write!(items, l, ox + x[i], oy + y[i], colour=:on_accent)
    elseif idea.depth == 1
      push!(items, Shape(shapes[i], left, top, bw, bh; fill=tone, line=nothing))
      write!(items, l, ox + x[i], oy + y[i], colour=:on_tone)
    else
      # A shape further out is a tint of its colour, so that the page's own text shows on it
      push!(items, Shape(shapes[i], left, top, bw, bh; fill=(tone, 0.16), line=tone, thick=0.09u))
      write!(items, l, ox + x[i], oy + y[i])
    end
  end
  Picture(w, oy + high + edge, items)
end

export mindmap
