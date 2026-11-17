# A timeline: periods in the order that they came, each with what happened in it.
#
#     timeline
#       title How the app grew
#       section The first year
#         2023 : Pages of Markdown : Tables
#         2024 : Diagrams
#              : Sums
#       section Now
#         2025 : Boards and charts
#
# A line is a period, then a colon and an event for each thing that happened
# in it. A line that starts with a colon gives more events to the period above
# it. `section` starts a group of periods, with its name over them. A colon
# between two digits, as in 9:30, is part of the words.
#
# The periods go from left to right along a line, with their events under
# them. Each section has a colour of its own, which its periods and their
# events share. Without sections, each period has its own colour. `timeline TD`
# is read, and the periods still go from left to right.

@use "./picture"...

"A period of a timeline, with what happened in it"
struct Period
  text::String
  events::Vector{String}
  section::Int      # the section that it's in, or 0
  line::Int         # the line of the code that it's on
end

"What the code of a timeline says: its title, the names of its sections and its periods"
read_timeline(code::AbstractString) = begin
  lines, title = statements(code)
  sections, periods = String[], Period[]
  for (n, line) in lines[2:end]
    if (m = match(r"^title\s+(.*)$", line)) !== nothing
      title = plain(m[1])
    elseif (m = match(r"^section\s+(.*)$", line)) !== nothing
      push!(sections, plain(m[1]))
    elseif occursin(r"^(accTitle|accDescr)\b", line)
      # Not drawn
    else
      # A colon parts a period from its events, and one event from the next. The colon of a time, like 9:30, parts nothing.
      pieces = [plain(piece) for piece in split(line, r"(?<!\d):|:(?!\d)")]
      if isempty(pieces[1])
        isempty(periods) && throw(Problem(n, "An event needs a period before its colon, like `2024 : What happened`"))
        append!(periods[end].events, filter(!isempty, pieces[2:end]))
      else
        push!(periods, Period(pieces[1], filter(!isempty, pieces[2:end]), length(sections), n))
      end
    end
  end
  (; title, sections, periods)
end

"The picture of the timeline that `code` describes, with its text measured by `pen`"
timeline(code::AbstractString, pen::Pen) = begin
  (; title, sections, periods) = read_timeline(code)
  isempty(periods) && return Picture(0.0, 0.0, Any[])
  u = pen.size
  small = 0.92u
  most = 10.5u    # the widest that the words of a period or an event can be before they go on to another line
  heads = [label(pen, p.text; most, bold=true) for p in periods]
  events = [[label(pen, e; most, size=small) for e in p.events] for p in periods]
  # Every period is as wide as the widest words need
  column = clamp(maximum(l.w for l in [heads; events...]) + 1.4u, 6u, most + 1.4u)
  gap = 0.8u
  # Each section has a colour, and so does each period that's in no section
  tone, last = 0, -1
  tones = map(periods) do p
    (p.section == 0 || p.section != last) && (tone += 1)
    last = p.section == 0 ? -1 : p.section
    tone
  end
  # The periods of each section that has some: the first and the last
  spans = [(s, findfirst(p -> p.section == s, periods), findlast(p -> p.section == s, periods)) for s in 1:length(sections)
           if any(p -> p.section == s, periods)]
  tops = [label(pen, sections[s]; most=(b - a + 1) * (column + gap) - gap - 1.2u, bold=true) for (s, a, b) in spans]

  items = Any[]
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.5u
  n = length(periods)
  across = n * column + (n - 1) * gap + 1.8u    # the line goes on past the last period, to its arrow
  w = max(across, heading.w) + 2edge
  ox = edge + max(0.0, (heading.w - across) / 2)
  left(i) = ox + (i - 1) * (column + gap)
  y = edge
  if !isempty(heading.lines)
    write!(items, heading, w / 2, edge + heading.h / 2)
    y += heading.h + 0.8u
  end
  if !isempty(spans)
    tall = maximum(l -> l.h, tops) + 0.9u
    for ((s, a, b), l) in zip(spans, tops)
      push!(items, Shape(:round, left(a), y, left(b) + column - left(a), tall; fill=tones[a], line=nothing))
      write!(items, l, (left(a) + left(b) + column) / 2, y + tall / 2, colour=:on_tone)
    end
    y += tall + 0.5u
  end
  head_h = maximum(l -> l.h, heads) + 1.0u
  line_y = y + head_h + 1.0u
  first_event = line_y + 1.0u
  bottom = line_y + 0.6u
  # The line of time, under the periods, with an arrow at the end that's latest
  push!(items, Stroke([(ox, line_y), (ox + across, line_y)]; colour=:link, thick=0.14u, to=:arrow, tip=0.9u))
  for (i, p) in enumerate(periods)
    x, middle, hue = left(i), left(i) + column / 2, tones[i]
    # A period in a section is a tint of the section's colour. A period by itself has all of its own colour.
    grouped = p.section != 0
    push!(items, Shape(:round, x, y, column, head_h; fill=grouped ? (hue, 0.4) : hue, line=grouped ? hue : nothing, thick=0.09u))
    write!(items, heads[i], middle, y + head_h / 2, colour=grouped ? :text : :on_tone)
    # A thin line joins the period to its place on the line of time, and to each of its events
    joined(a, b) = push!(items, Stroke([(middle, a), (middle, b)]; colour=hue, thick=0.1u))
    joined(y + head_h, isempty(events[i]) ? line_y : first_event)
    push!(items, Shape(:circle, middle - 0.32u, line_y - 0.32u, 0.64u, 0.64u; fill=hue, line=:surface, thick=0.12u))
    at = first_event
    for (k, l) in enumerate(events[i])
      tall = l.h + 0.8u
      k > 1 && joined(at - 0.5u, at)
      push!(items, Shape(:rect, x, at, column, tall; fill=(hue, 0.16), line=hue, thick=0.08u))
      write!(items, l, middle, at + tall / 2)
      at += tall + 0.5u
    end
    isempty(events[i]) || (bottom = max(bottom, at - 0.5u))
  end
  Picture(w, bottom + edge, items)
end

export timeline
