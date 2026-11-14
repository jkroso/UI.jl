# Where the boxes of a diagram go, and the path of each line between two of them.
#
#     boxes = [Box(80, 40), Box(80, 40), Box(60, 60, shape=:diamond)]
#     links = [Link(1, 2), Link(2, 3, lw=30, lh=16)]
#     w, h = arrange!(boxes, links, dir=:TB)
#
# `arrange!` gives each box the place of its middle, in `x` and `y`. It gives
# each link its `path`, and the middle of its label in `lx` and `ly`.
#
# The boxes go in rows. A link goes from a box to one in a row further down, so
# most lines point the same way. The boxes of a row are in the order that makes
# the fewest lines cross, and each box is as near as it can be to the boxes
# that it has lines to. With `dir=:LR` the rows are columns, and :BT and :RL
# are the other way up.
#
# A box can be in another box, as `inside` says. The boxes in a box are
# arranged by themselves first, which gives the outer box its size.

@use "./picture" Point

"A box of a diagram: a node of a flowchart, a class, a state, or a box with other boxes in it"
mutable struct Box
  w::Float64
  h::Float64
  shape::Symbol      # :rect, :diamond or :circle: where a line that meets the box stops
  inside::Int        # the box that it's in, or 0
  dir::Symbol        # for a box with boxes in it: the way that those go
  head::Float64      # ... and the room at its top for its title
  least::Float64     # ... and the least that it can be wide, so that its title fits
  pad::Float64       # ... and the room between its edge and its boxes, or -1 for the usual room
  x::Float64         # its middle
  y::Float64
end
Box(w, h; shape=:rect, inside=0, dir=:TB, head=0.0, least=0.0, pad=-1.0) = Box(w, h, shape, inside, dir, head, least, pad, 0.0, 0.0)

"A line from one box to another"
mutable struct Link
  from::Int
  to::Int
  lw::Float64        # how wide and how tall its label is, or 0 without one
  lh::Float64
  len::Int           # the least number of rows that it goes down
  dir::Symbol        # the way that the rows it goes over run. `arrange!` sets it.
  path::Vector{Point}   # as the points of a curved Stroke
  lx::Float64        # the middle of its label
  ly::Float64
end
Link(from, to; lw=0.0, lh=0.0, len=1) = Link(from, to, lw, lh, len, :TB, Point[], 0.0, 0.0)

across(dir::Symbol) = dir in (:LR, :RL)

# --- rows -------------------------------------------------------------------------

"""
Give each box of a row the place nearest the one it wants, with the boxes in
their order and each pair at least as far apart as `gaps` says. `weight` says
how much each box's wish counts.
"""
spread(want, weight, gaps) = begin
  n = length(want)
  n == 0 && return Float64[]
  # With the least room taken off, the boxes only need to be in order, which is quick to solve:
  # two neighbours that are out of order share the place between them, by weight
  room = zeros(n)
  for i in 2:n
    room[i] = room[i-1] + gaps[i-1]
  end
  mean, heavy, count = Float64[], Float64[], Int[]
  for i in 1:n
    push!(mean, want[i] - room[i]); push!(heavy, weight[i]); push!(count, 1)
    while length(mean) > 1 && mean[end-1] > mean[end]
      total = heavy[end-1] + heavy[end]
      mean[end-1] = (mean[end-1] * heavy[end-1] + mean[end] * heavy[end]) / total
      heavy[end-1] = total
      count[end-1] += count[end]
      pop!(mean); pop!(heavy); pop!(count)
    end
  end
  out = Float64[]
  for (m, c) in zip(mean, count), _ in 1:c
    push!(out, m)
  end
  out .+ room
end

"""
Where each box is along its row, with as many lines as can be straight. `layers`
holds each row's boxes in their order, `up` and `down` the boxes that each box
has lines to in the row above and the row below, and `gap(v, w)` the least
distance between the middles of two neighbours.

This is the method of Brandes and Köpf. Each box lines up with the middle one
of the boxes that it has lines to, in a column, and the columns are packed side
by side. That's done four times: with the lines up or the lines down, and
packed from the left or from the right. A box goes between the middle two of
its four places.
"""
straight(layers, up, down, real, widths, gap) = begin
  total = length(widths)
  at = zeros(Int, total)
  for layer in layers, (k, v) in enumerate(layer)
    at[v] = k
  end
  # A line between two boxes that crosses a line that goes over many rows doesn't get to be straight: the long line does
  clash = Set{Tuple{Int,Int}}()
  inner(v) = real[v] ? 0 : something(findfirst(u -> !real[u], up[v]), 0)
  for r in 2:length(layers)
    layer, before = layers[r], length(layers[r-1])
    k0, scanned = 0, 1
    for (i, v) in enumerate(layer)
      w = inner(v) == 0 ? 0 : up[v][inner(v)]
      (w != 0 || i == length(layer)) || continue
      k1 = w != 0 ? at[w] : before + 1
      for other in layer[scanned:i], u in up[other]
        (at[u] < k0 || k1 < at[u]) && !(!real[u] && !real[other]) && push!(clash, minmax(u, other))
      end
      scanned, k0 = i + 1, k1
    end
  end
  places = Vector{Float64}[]
  for upward in (true, false), leftward in (true, false)
    rows = upward ? layers : reverse(layers)
    leftward || (rows = reverse.(rows))
    near = upward ? up : down
    place = zeros(Int, total)
    for row in rows, (k, v) in enumerate(row)
      place[v] = k
    end
    # Each box joins the column of the middle one of its neighbours, if no box of its row has gone past that column
    root, align = collect(1:total), collect(1:total)
    for row in rows
      reached = 0
      for v in row
        ws = sort(near[v], by=w -> place[w])
        isempty(ws) && continue
        middle = (length(ws) + 1) / 2
        for w in ws[floor(Int, middle):ceil(Int, middle)]
          if align[v] == v && reached < place[w] && !(minmax(v, w) in clash)
            align[w] = v
            align[v] = root[v] = root[w]
            reached = place[w]
          end
        end
      end
    end
    # Pack the columns: each is as far left as the column before it in any row lets it be ...
    after = Dict{Int,Dict{Int,Float64}}()
    before = Dict{Int,Dict{Int,Float64}}()
    for row in rows, k in 2:length(row)
      a, b = root[row[k-1]], root[row[k]]
      d = gap(row[k-1], row[k])
      get!(() -> Dict{Int,Float64}(), after, a)[b] = max(get(get(after, a, Dict{Int,Float64}()), b, 0.0), d)
      get!(() -> Dict{Int,Float64}(), before, b)[a] = after[a][b]
    end
    roots = unique(root)
    xs = Dict{Int,Float64}()
    reach(v) = get!(xs, v) do
      maximum(reach(a) + d for (a, d) in get(before, v, Dict{Int,Float64}()); init=0.0)
    end
    foreach(reach, roots)
    # ... and then as far right as the column after it lets it be, which closes the gaps that the first pass left
    done = Set{Int}()
    settle(v) = begin
      v in done && return
      push!(done, v)
      least = Inf
      for (b, d) in get(after, v, Dict{Int,Float64}())
        settle(b)
        least = min(least, xs[b] - d)
      end
      least < Inf && (xs[v] = max(xs[v], least))
    end
    foreach(settle, roots)
    out = [xs[root[v]] for v in 1:total]
    push!(places, leftward ? out : -out)
  end
  # Line the four up with the narrowest of them: the two packed from the left by their left sides, the others by their right
  span(p) = (minimum(p[v] - widths[v] / 2 for v in 1:total), maximum(p[v] + widths[v] / 2 for v in 1:total))
  lo, hi = span(places[argmin([span(p)[2] - span(p)[1] for p in places])])
  for (i, p) in enumerate(places)
    p .+= isodd(i) ? lo - span(p)[1] : hi - span(p)[2]
  end
  [(s = sort([p[v] for p in places]); (s[2] + s[3]) / 2) for v in 1:total]
end

"How many pairs of lines cross between two rows. Each line is the place of its end in the upper row and in the lower one."
crossings(lines) = begin
  n = 0
  for i in 1:length(lines), j in i+1:length(lines)
    (a, b), (c, d) = lines[i], lines[j]
    n += (a < c && b > d) || (a > c && b < d)
  end
  n
end

"""
Arrange boxes of the sizes `ws` and `hs` in rows. `es` holds a line as
`(from, to, lw, lh, len)`. Returns the middle of each box, the points that
each line goes through between its two boxes, the middle of each line's label,
and how wide and how tall it all is.
"""
rows(ws, hs, es; dir=:TB, nodesep=40.0, ranksep=44.0) = begin
  n = length(ws)
  n == 0 && return (Point[], Vector{Point}[], Point[], 0.0, 0.0)
  flat = across(dir)
  # A diagram that goes across is laid out as one that goes down, on its side
  flat && ((ws, hs) = (hs, ws))
  es = [(a, b, flat ? lh : lw, flat ? lw : lh, max(len, lw > 0 ? 2 : 1)) for (a, b, lw, lh, len) in es]
  # A second line between the same two boxes goes over two rows, so that it has a path of its own
  seen = Set{Tuple{Int,Int}}()
  for (i, (a, b, lw, lh, len)) in enumerate(es)
    pair = minmax(a, b)
    pair in seen ? (es[i] = (a, b, lw, lh, max(len, 2))) : push!(seen, pair)
  end

  # 1. Turn round the lines that close a loop, so that every line goes down
  out = [Int[] for _ in 1:n]
  foreach(((i, e),) -> push!(out[e[1]], i), enumerate(es))
  turned = falses(length(es))
  state = zeros(Int, n)   # 1 while a box's lines are being followed, 2 once they have been
  follow(v) = begin
    state[v] = 1
    for i in out[v]
      w = es[i][2]
      state[w] == 1 ? (turned[i] = true) : state[w] == 0 && follow(w)
    end
    state[v] = 2
  end
  foreach(v -> state[v] == 0 && follow(v), 1:n)
  top(i) = turned[i] ? es[i][2] : es[i][1]
  bottom(i) = turned[i] ? es[i][1] : es[i][2]

  # 2. The row of each box: as far up as its lines let it be
  below = [Int[] for _ in 1:n]
  above = [Int[] for _ in 1:n]
  for i in 1:length(es)
    push!(below[top(i)], i); push!(above[bottom(i)], i)
  end
  waiting = [length(above[v]) for v in 1:n]
  ready = [v for v in 1:n if waiting[v] == 0]
  order = Int[]
  row = zeros(Int, n)
  while !isempty(ready)
    v = popfirst!(ready)
    push!(order, v)
    for i in below[v]
      w = bottom(i)
      row[w] = max(row[w], row[v] + es[i][5])
      (waiting[w] -= 1) == 0 && push!(ready, w)
    end
  end
  # A box with more lines down than up moves down to the boxes under it, which makes its lines short
  for v in reverse(order)
    (isempty(below[v]) || length(below[v]) <= length(above[v])) && continue
    row[v] = max(row[v], minimum(row[bottom(i)] - es[i][5] for i in below[v]))
  end
  row .-= minimum(row)
  deep = maximum(row) + 1

  # 3. A line that goes over a row gets a point in it, which takes a place among that row's boxes.
  #    The label of a line is the point in its middle row.
  vw, vh, vrow, real = collect(Float64, ws), collect(Float64, hs), copy(row), fill(true, n)
  up = [Int[] for _ in 1:n]
  down = [Int[] for _ in 1:n]
  chains = Vector{Int}[]
  labels = zeros(Int, length(es))
  for i in 1:length(es)
    a, b = top(i), bottom(i)
    chain = [a]
    middle = row[a] + (row[b] - row[a]) ÷ 2
    for r in row[a]+1:row[b]-1
      labelled = r == middle && es[i][3] > 0
      push!(vw, labelled ? es[i][3] : 0.0); push!(vh, labelled ? es[i][4] : 0.0); push!(vrow, r); push!(real, false)
      push!(up, Int[]); push!(down, Int[])
      labelled && (labels[i] = length(vw))
      push!(chain, length(vw))
    end
    push!(chain, b)
    for k in 2:length(chain)
      push!(down[chain[k-1]], chain[k]); push!(up[chain[k]], chain[k-1])
    end
    push!(chains, chain)
  end
  total = length(vw)

  # 4. The order of each row: the one with the fewest lines that cross
  layers = [Int[] for _ in 1:deep]
  placed = falses(total)
  place(v) = begin
    placed[v] && return
    placed[v] = true
    push!(layers[vrow[v]+1], v)
    foreach(place, down[v])
  end
  foreach(place, sort(1:n, by=v -> (row[v], v)))
  at = zeros(Int, total)
  number!() = for layer in layers, (k, v) in enumerate(layer)
    at[v] = k
  end
  crossed() = begin
    number!()
    sum(crossings([(at[v], at[w]) for v in layer for w in down[v]]) for layer in layers)
  end
  best, fewest = deepcopy(layers), crossed()
  for sweep in 1:24
    fewest == 0 && break
    near = isodd(sweep) ? up : down
    for r in (isodd(sweep) ? (2:deep) : (deep-1:-1:1))
      number!()
      # Each box goes to the middle of the boxes that it has lines to in the row before
      sort!(layers[r], by=v -> isempty(near[v]) ? Float64(at[v]) : sum(at[w] for w in near[v]) / length(near[v]), alg=MergeSort)
    end
    now = crossed()
    now < fewest && ((best, fewest) = (deepcopy(layers), now))
  end
  layers = best
  # Then swap two neighbours wherever that makes fewer lines cross
  improved = fewest > 0
  while improved
    improved = false
    for layer in layers, k in 1:length(layer)-1
      number!()
      v, w = layer[k], layer[k+1]
      cost(pv, pw) = begin
        c = 0
        for near in (up, down), a in near[v], b in near[w]
          c += (pv < pw) != (at[a] < at[b]) && at[a] != at[b]
        end
        c
      end
      if cost(k + 1, k) < cost(k, k + 1)
        layer[k], layer[k+1] = w, v
        improved = true
      end
    end
  end
  number!()

  # 5. Where each box is along its row
  gap(v, w) = (vw[v] + vw[w]) / 2 + (real[v] && real[w] ? nodesep : real[v] || real[w] ? nodesep / 2 : nodesep / 3)
  x = straight(layers, up, down, real, vw, gap)

  # 6. How far down each row is
  tall = [maximum(vh[v] for v in layer; init=0.0) for layer in layers]
  solid = [any(real[v] for v in layer) for layer in layers]
  y = zeros(total)
  edge = 0.0
  for r in 1:deep
    r > 1 && (edge += solid[r-1] && solid[r] ? ranksep : ranksep / 2)
    foreach(v -> y[v] = edge + tall[r] / 2, layers[r])
    edge += tall[r]
  end
  left = minimum(x[v] - vw[v] / 2 for v in 1:total)
  x .-= left
  wide = maximum(x[v] + vw[v] / 2 for v in 1:total)
  # :BT and :RL are the same, the other way up
  dir in (:BT, :RL) && (y .= edge .- y)
  point(v) = flat ? (y[v], x[v]) : (x[v], y[v])
  ways = map(1:length(es)) do i
    way = [point(v) for v in chains[i][2:end-1]]
    turned[i] ? reverse(way) : way
  end
  (point.(1:n), ways, [l == 0 ? (0.0, 0.0) : point(l) for l in labels], flat ? edge : wide, flat ? wide : edge)
end

# --- lines --------------------------------------------------------------------------

"""
Where a line from the box `b` towards the point `q` leaves the box, and the
way that it goes as it leaves. It leaves from the side that faces the next row.
"""
port(b::Box, q::Point, flat::Bool) = begin
  # Worked out for rows that go down. A diagram that goes across is the same on its side.
  bc, bm, bw, bh = flat ? (b.y, b.x, b.h, b.w) : (b.x, b.y, b.w, b.h)
  qc, qm = flat ? (q[2], q[1]) : q
  c, m, tc, tm = if abs(qm - bm) < bh / 2 + 1
    # The point is beside the box, so the line leaves from the box's side
    s = qc >= bc ? 1.0 : -1.0
    (bc + s * bw / 2, bm, s, 0.0)
  else
    s = qm >= bm ? 1.0 : -1.0
    # A line to a box that's off to one side leaves a little to that side of the middle
    dc = clamp((qc - bc) * 0.3, -0.3bw, 0.3bw)
    reach = b.shape == :diamond ? bh / 2 * (1 - abs(dc) / (bw / 2)) :
            b.shape == :circle ? bh / 2 * sqrt(max(0.0, 1 - (dc / (bw / 2))^2)) : bh / 2
    (bc + dc, bm + s * reach, 0.0, s)
  end
  flat ? ((m, c), (tm, tc)) : ((c, m), (tc, tm))
end

"The curve from the box `a` to the box `b` through the points `way`, as the points of a curved Stroke"
curve(a::Box, b::Box, way::Vector{Point}, dir::Symbol) = begin
  flat = across(dir)
  start, leave = port(a, isempty(way) ? (b.x, b.y) : way[1], flat)
  finish, arrive = port(b, isempty(way) ? (a.x, a.y) : way[end], flat)
  points = [start; way; finish]
  main(p) = flat ? p[1] : p[2]
  # The way that the line goes at each point: along its ends, and from row to row between them
  ways = map(1:length(points)) do i
    i == 1 && return leave
    i == length(points) && return (-arrive[1], -arrive[2])
    s = main(points[i+1]) >= main(points[i-1]) ? 1.0 : -1.0
    flat ? (s, 0.0) : (0.0, s)
  end
  out = [points[1]]
  for i in 2:length(points)
    p, q, u, v = points[i-1], points[i], ways[i-1], ways[i]
    # Each end pulls the curve half of the way to the other end, along the way that it goes
    reach(t) = 0.5 * abs(t[1] != 0 ? q[1] - p[1] : q[2] - p[2])
    push!(out, (p[1] + u[1] * reach(u), p[2] + u[2] * reach(u)), (q[1] - v[1] * reach(v), q[2] - v[2] * reach(v)), q)
  end
  out
end

"The path of a line from a box to itself: a loop at the box's right"
loop(b::Box) = begin
  x, r = b.x + b.w / 2, min(b.h / 4, 12.0)
  [(x, b.y - r), (x + 3r, b.y - 1.5r), (x + 3r, b.y + 1.5r), (x, b.y + r)]
end

# --- boxes in boxes -----------------------------------------------------------------

"""
Arrange `boxes` and the `links` between them. A box that has other boxes in it
gets its size from them, with `pad` around them. Returns how wide and how tall
it all is.
"""
arrange!(boxes::Vector{Box}, links::Vector{Link}; dir=:TB, nodesep=40.0, ranksep=44.0, pad=16.0) = begin
  kids = Dict{Int,Vector{Int}}()
  foreach(((i, b),) -> push!(get!(kids, b.inside, Int[]), i), enumerate(boxes))
  # The boxes that each box is in, from the outermost one in
  chain(i) = (c = [i]; while boxes[c[1]].inside != 0; pushfirst!(c, boxes[c[1]].inside) end; c)
  chains = chain.(1:length(boxes))
  # Each link belongs to the innermost box that holds both of its ends. In that box it goes
  # between the two boxes that hold its ends.
  owned = Dict{Int,Vector{Tuple{Int,Int,Int}}}()
  for (i, l) in enumerate(links)
    a, b = chains[l.from], chains[l.to]
    k = 1
    while k <= min(length(a), length(b)) && a[k] == b[k]
      k += 1
    end
    (k > length(a) || k > length(b)) && continue   # one end is in the other, or they're the same box
    push!(get!(owned, k == 1 ? 0 : a[k-1], Tuple{Int,Int,Int}[]), (i, a[k], b[k]))
  end
  local_at = Dict{Int,Point}()          # the middle of each box, from the corner of the box that it's in
  local_ways = Dict{Int,Vector{Point}}()
  local_labels = Dict{Int,Point}()
  shift = Dict{Int,Point}()             # where the boxes in a box start, from the box's corner
  place(c) = begin
    members = get(kids, c, Int[])
    foreach(m -> haskey(kids, m) && place(m), members)
    way = c == 0 ? dir : boxes[c].dir
    index = Dict(m => k for (k, m) in enumerate(members))
    mine = get(owned, c, Tuple{Int,Int,Int}[])
    es = [(index[a], index[b], links[i].lw, links[i].lh, links[i].len) for (i, a, b) in mine]
    at, ways, labels, w, h = rows([boxes[m].w for m in members], [boxes[m].h for m in members], es; dir=way, nodesep, ranksep)
    foreach(((k, m),) -> local_at[m] = at[k], enumerate(members))
    for (k, (i, _, _)) in enumerate(mine)
      links[i].dir = way
      local_ways[i], local_labels[i] = ways[k], labels[k]
    end
    c == 0 && return (w, h)
    box = boxes[c]
    room = box.pad < 0 ? pad : box.pad
    box.w = max(w + 2room, box.least)
    box.h = h + 2room + box.head
    shift[c] = ((box.w - w) / 2, room + box.head)
    (box.w, box.h)
  end
  size = place(0)
  # Now that each box has its size, work out where each one is in the whole diagram
  corner = Dict{Int,Point}(0 => (0.0, 0.0))
  settle(c) = for m in get(kids, c, Int[])
    p = local_at[m] .+ corner[c]
    boxes[m].x, boxes[m].y = p
    if haskey(kids, m)
      corner[m] = (p[1] - boxes[m].w / 2, p[2] - boxes[m].h / 2) .+ shift[m]
      settle(m)
    end
  end
  settle(0)
  for (c, mine) in owned, (i, _, _) in mine
    l = links[i]
    way = [p .+ corner[c] for p in local_ways[i]]
    l.path = curve(boxes[l.from], boxes[l.to], way, l.dir)
    l.lx, l.ly = local_labels[i] .+ corner[c]
  end
  for l in links
    l.from == l.to && (l.path = loop(boxes[l.from]); l.lx = boxes[l.from].x + boxes[l.from].w / 2 + 40; l.ly = boxes[l.from].y)
  end
  size
end

export Box, Link, arrange!, across
