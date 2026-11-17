# A Gantt chart: the tasks of a project, each a bar on a line of days.
#
#     gantt
#       title A page for the shop
#       dateFormat YYYY-MM-DD
#       excludes weekends
#       section Design
#         Draw the page  :done, draw, 2024-03-04, 3d
#         Ask the owner  :active, ask, after draw, 2d
#       section Build
#         Write the code :crit, code, after ask, 5d
#         Open the shop  :milestone, after code, 0d
#
# A task is its name, a colon, and up to three things with commas between
# them: an id, when it starts and when it ends. Before those it can have the
# marks `done`, `active`, `crit` and `milestone`.
#
#   - It starts on a date, or `after` the ids of other tasks, when the last of
#     them ends. A task with no start begins when the task above it ends.
#   - It ends on a date, or after a length like `3d`, `2w` or `36h`, or `until`
#     the id of another task, when that one starts.
#
# `dateFormat` says how the dates are written, with YYYY, MM, DD, HH, mm and
# the rest of what Mermaid reads. `excludes` names the days when no work is
# done: `weekends`, a day of the week or a date. A task that has a length
# takes that many working days, so it ends later when it goes over a day
# that's left out. `section` starts a group of tasks, with its name at the
# left. A task with `vert` is a line down the chart, and takes no row.
#
# The days go across the top as they do in a calendar: the months, and under
# them each day or each Monday when there's room. `axisFormat`, `tickInterval`
# and `todayMarker` are read and change nothing.

@use "./picture"...
@use Dates: Dates, Date, DateTime, Day, Month, Year, Millisecond, Minute, DateFormat

"A task of a Gantt chart"
mutable struct Job
  name::String
  id::String
  section::Int             # the section that it's in, or 0 for a task that's before the first one
  line::Int                # the line of the code that it's on
  marks::Vector{String}    # done, active, crit, milestone, vert
  start::Any               # as the code says: a DateTime, the ids of the tasks that it's after, or nothing for the task above
  finish::Any              # a DateTime, a length as a number and its unit, or the ids of the tasks that it's until
  from::Union{DateTime,Nothing}   # when it starts, once that's worked out
  to::Union{DateTime,Nothing}     # when its bar ends
  next::Union{DateTime,Nothing}   # when a task that's after it can start: later than `to` when days are left out
end

"True when the task `j` has the mark `mark`, like \"done\""
has(j::Job, mark) = mark in j.marks

# How many milliseconds each unit of a length is. A month and a year are counted on the calendar.
const UNITS = Dict("ms" => 1.0, "s" => 1e3, "m" => 6e4, "h" => 3.6e6, "d" => 8.64e7, "w" => 6.048e8)
const LONGEST = 200 * 365.25 * 8.64e7    # the longest that a task or a chart can be, in milliseconds
const LENGTH = r"^(\d+(?:\.\d+)?|\.\d+)(ms|s|m|h|d|w|M|y)$"
const MARKS = ("done", "active", "crit", "milestone", "vert")
const DAY_NAMES = Dict(lowercase(Dates.dayname(k)) => k for k in 1:7)
# What Julia calls each part of a date that Mermaid's `dateFormat` can have
const PIECES = Dict("YYYY" => "yyyy", "YY" => "yy", "MMMM" => "U", "MMM" => "u", "MM" => "mm", "M" => "m", "DD" => "dd", "D" => "d",
                    "HH" => "HH", "H" => "H", "hh" => "II", "h" => "I", "mm" => "MM", "m" => "M", "ss" => "SS", "s" => "S",
                    "SSS" => "sss", "A" => "p", "a" => "p")

"How dates are read when the code of a chart says that they're written like `text`, as in `DD/MM/YYYY`"
date_format(text::AbstractString) =
  DateFormat(replace(strip(text), r"YYYY|YY|MMMM|MMM|MM|M|DD|D|HH|H|hh|h|mm|m|ss|s|SSS|A|a|[A-Za-z]" => p -> get(PIECES, p, "\\" * p)))

"The time that `text` says, written like `like`, or nothing if it isn't written that way"
moment(text::AbstractString, like::AbstractString) = begin
  t = try
    tryparse(DateTime, strip(text), date_format(like))
  catch
    nothing
  end
  t === nothing && return nothing
  # A year of two numbers is in this century
  occursin("YY", like) && !occursin("YYYY", like) && Dates.year(t) < 100 ? t + Year(2000) : t
end

"The time that's `length`, a number and its unit, after `from`"
later(from::DateTime, (value, unit)) =
  unit == "M" ? (isinteger(value) ? from + Month(Int(value)) : from + Millisecond(round(Int, value * 30 * 8.64e7))) :
  unit == "y" ? (isinteger(value) ? from + Year(Int(value)) : from + Millisecond(round(Int, value * 365 * 8.64e7))) :
  from + Millisecond(round(Int, value * UNITS[unit]))

"""
When a task that goes from `from` to `to` ends, with a day more for each day
that it goes over when no work is done. `off(day)` is true for such a day.
Returns when the tasks after it can start, and when its bar ends. The two
differ when the task ends just before days that are left out.
"""
stretched(from::DateTime, to::DateTime, off) = begin
  day, shown, bad = from + Day(1), to, false
  while day <= to
    bad || (shown = to)
    bad = off(Date(day))
    bad && (to += Day(1))
    day += Day(1)
  end
  to, shown
end

"""
What the code of a Gantt chart says: its title, the names of its sections and
its tasks, each with the times that it starts and ends. `off(day)` is true
for a day when no work is done, and `rests` is true when there are such days.
`today` is when a first task that has no start begins.
"""
read_gantt(code::AbstractString; today::Date=Dates.today()) = begin
  lines, title = statements(code)
  like = "YYYY-MM-DD"
  sections, jobs = String[], Job[]
  written = Tuple{Int,String,String,Int}[]       # each task as it's written: its line, its name, what's after the colon, its section
  left_out, kept = Tuple{Int,String}[], Tuple{Int,String}[]
  weekend, inclusive = 6, false
  for (n, line) in lines[2:end]
    if (m = match(r"^title\s+(.*)$", line)) !== nothing
      title = plain(m[1])
    elseif (m = match(r"^dateFormat\s+(.*)$", line)) !== nothing
      like = String(strip(m[1]))
    elseif (m = match(r"^(excludes|includes)\s+(.*)$", line)) !== nothing
      append!(m[1] == "excludes" ? left_out : kept, [(n, String(word)) for word in split(m[2], r"[\s,]+", keepempty=false)])
    elseif (m = match(r"^weekend\s+(friday|saturday)$"i, line)) !== nothing
      weekend = lowercase(m[1]) == "friday" ? 5 : 6
    elseif line == "inclusiveEndDates"
      inclusive = true
    elseif (m = match(r"^section\s+(.*)$", line)) !== nothing
      push!(sections, plain(m[1]))
    elseif occursin(r"^(axisFormat|tickInterval|weekday|todayMarker|topAxis|click|accTitle|accDescr)\b", line)
      # Not drawn
    elseif (m = match(r"^([^:]+):(.*)$", line)) !== nothing
      push!(written, (n, plain(m[1]), String(m[2]), length(sections)))
    else
      throw(Problem(n, "A task is its name, a colon and its days, like `Write it :2024-03-04, 3d`"))
    end
  end
  # The days when no work is done
  weekends, days, dates, working = false, Set{Int}(), Set{Date}(), Set{Date}()
  date(n, word) = begin
    t = something(moment(word, like), moment(word, "YYYY-MM-DD"), Some(nothing))
    t === nothing && throw(Problem(n, "\"$word\" isn't `weekends`, a day of the week or a date like $like"))
    Date(t)
  end
  for (n, word) in left_out
    lowercase(word) == "weekends" ? (weekends = true) :
    haskey(DAY_NAMES, lowercase(word)) ? push!(days, DAY_NAMES[lowercase(word)]) : push!(dates, date(n, word))
  end
  foreach(((n, word),) -> push!(working, date(n, word)), kept)
  off(d::Date) = !(d in working) && ((weekends && Dates.dayofweek(d) in (weekend, weekend + 1)) || Dates.dayofweek(d) in days || d in dates)
  rests = weekends || !isempty(days) || !isempty(dates)

  for (n, name, said, section) in written
    things = filter(!isempty, String.(strip.(split(said, ','))))
    marks = String[]
    while !isempty(things) && things[1] in MARKS
      push!(marks, popfirst!(things))
    end
    isempty(things) && throw(Problem(n, "A task needs a length or an end after its colon, like `3d`"))
    length(things) > 3 && throw(Problem(n, "A task has an id, a start and an end at the most. This one has $(length(things)) things."))
    id = length(things) == 3 ? things[1] : "task$(length(jobs) + 1)"
    start = if length(things) == 1
      nothing
    elseif (m = match(r"^after\s+(.+)$", things[end-1])) !== nothing
      String.(split(m[1]))
    else
      t = moment(things[end-1], like)
      t === nothing && throw(Problem(n, "\"$(things[end-1])\" isn't a date like $like, or `after` and the id of a task"))
      t
    end
    finish = if (m = match(r"^until\s+(.+)$", things[end])) !== nothing
      String.(split(m[1]))
    elseif (m = match(LENGTH, things[end])) !== nothing
      (parse(Float64, m[1]), String(m[2]))
    else
      t = moment(things[end], like)
      t === nothing && throw(Problem(n, "\"$(things[end])\" isn't a length like `3d`, a date like $like, or `until` and the id of a task"))
      inclusive ? t + Day(1) : t
    end
    push!(jobs, Job(name, id, section, n, marks, start, finish, nothing, nothing, nothing))
  end

  # A task can wait for one that's further down, so the times are worked out in as many goes as that takes
  named = Dict(j.id => k for (k, j) in enumerate(jobs))
  known(n, ids) = map(ids) do id
    haskey(named, id) || throw(Problem(n, "No task has the id `$id`"))
    jobs[named[id]]
  end
  left = length(jobs)
  while left > 0
    for (k, j) in enumerate(jobs)
      j.to === nothing || continue
      if j.from === nothing
        if j.start isa DateTime
          j.from = j.start
        elseif j.start === nothing
          k == 1 ? (j.from = DateTime(today)) : jobs[k-1].next === nothing || (j.from = jobs[k-1].next)
        else
          others = known(j.line, j.start)
          all(o -> o.next !== nothing, others) && (j.from = maximum(o -> o.next, others))
        end
      end
      j.from === nothing && continue
      if j.finish isa DateTime
        j.to = j.next = j.finish
      elseif j.finish isa Tuple
        j.finish[1] * get(UNITS, j.finish[2], j.finish[2] == "M" ? 2.6e9 : 3.2e10) > LONGEST && throw(Problem(j.line, "This task is longer than 200 years"))
        j.next, j.to = rests ? stretched(j.from, later(j.from, j.finish), off) : (later(j.from, j.finish), later(j.from, j.finish))
      else
        others = known(j.line, j.finish)
        all(o -> o.from !== nothing, others) && (j.to = j.next = minimum(o -> o.from, others))
      end
    end
    still = count(j -> j.to === nothing, jobs)
    still == left && throw(Problem(jobs[findfirst(j -> j.to === nothing, jobs)].line, "This task waits for a task that waits for it"))
    left = still
  end
  if !isempty(jobs)
    span = Dates.value(maximum(j -> max(j.from, j.to), jobs) - minimum(j -> j.from, jobs))
    span > LONGEST && throw(Problem(0, "The chart is longer than 200 years"))
  end
  (; title, sections, jobs, off, rests)
end

# How far apart the times over a chart of hours or minutes can be, in minutes
const STEPS = [1, 2, 5, 10, 15, 30, 60, 120, 180, 360, 720, 1440]

"How long it is from `a` to `b`, in milliseconds"
since(a::DateTime, b::DateTime) = Float64(Dates.value(b - a))

"The picture of the Gantt chart that `code` describes, with its text measured by `pen`"
gantt(code::AbstractString, pen::Pen) = begin
  (; title, sections, jobs, off, rests) = read_gantt(code)
  isempty(jobs) && return Picture(0.0, 0.0, Any[])
  u = pen.size
  small, tiny = 0.9u, 0.82u
  tasks, marks = [j for j in jobs if !has(j, "vert")], [j for j in jobs if has(j, "vert")]
  starts, ends = minimum(j -> j.from, jobs), maximum(j -> max(j.from, j.to), jobs)
  # A chart of less than two days that has a time of day in it shows hours and minutes. Any other shows days.
  clock = since(starts, ends) < 2 * 8.64e7 && any(j -> Dates.Time(j.from) != Dates.Time(0) || Dates.Time(j.to) != Dates.Time(0), jobs)
  # `lo` and `hi` are the times at the chart's two edges, `each` is how long one step along it is, and `step` how wide that is
  if clock
    minutes = STEPS[something(findfirst(s -> since(starts, ends) / (6e4 * s) <= 12, STEPS), length(STEPS))]
    each = Minute(minutes)
    lo, hi = floor(starts, each), max(ceil(ends, each), floor(starts, each) + each)
    step = max(46u / (since(lo, hi) / since(lo, lo + each)), 3.6u)
  else
    each = Day(1)
    lo, hi = DateTime(Date(starts)), max(ceil(ends, Day), DateTime(Date(starts)) + Day(1))
    step = clamp(46u / (since(lo, hi) / 8.64e7), 0.01u, 2.6u)
  end
  per = step / since(lo, lo + each)                 # px to a millisecond
  # A milestone at the chart's first moment has a step before it, so that all of its diamond is in the chart
  any(j -> has(j, "milestone") && since(lo, j.from + (j.to - j.from) ÷ 2) * per < 0.65u, tasks) && (lo -= each)
  across(t) = since(lo, t) * per                    # how far along the chart a time is

  # Each task's bar, and its name: in the bar when it fits, or else beside it
  bar_h, row_h = 1.55u, 2.3u
  names = [label(pen, replace(j.name, '\n' => ' '), size=small) for j in tasks]
  wide_now = since(lo, hi) * per
  spans = map(tasks) do j
    has(j, "milestone") ? (m = across(j.from + (j.to - j.from) ÷ 2); (m - 0.65u, m + 0.65u)) : (across(j.from), max(across(j.to), across(j.from) + 0.3u))
  end
  places = map(1:length(tasks)) do i
    (a, b), l, j = spans[i], names[i], tasks[i]
    tick = has(j, "done") && !has(j, "milestone") && b - a >= 1.5u ? 1.1u : 0.0
    !has(j, "milestone") && l.w + 1.0u + tick <= b - a ? (:in, (a + tick + b) / 2) :
    b + 0.5u + l.w <= wide_now || a - 0.5u - l.w < 0 ? (:right, b + 0.5u) : (:left, a - 0.5u - l.w)
  end
  # The chart goes on for as many steps as the last bars and the names beside them need
  need = maximum(places[i][1] == :right ? places[i][2] + names[i].w + 0.4u : spans[i][2] for i in 1:length(tasks); init=0.0)
  more = max(0, ceil(Int, (need - wide_now) / step))
  hi += each * more
  wide_chart = since(lo, hi) * per

  # The sections go down the left, each as tall as its tasks, or as its name when that's taller
  heads = [label(pen, s, most=10u, size=small, bold=true) for s in sections]
  names_w = isempty(sections) ? 0.0 : maximum(l -> l.w, heads) + 1.4u
  heading = label(pen, title, bold=true, size=1.1u)
  edge = 0.5u
  each_day = !clock && step >= 1.5u
  each_week = !clock && !each_day && 7step >= 3.6u
  dates_h = clock || each_day || each_week ? 3.5u : 2.1u
  left = edge + names_w
  top = edge + (isempty(heading.lines) ? 0.0 : heading.h + 0.8u)
  rows_top = top + dates_h
  row_y = zeros(length(tasks))
  bands = Tuple{Int,Float64,Float64}[]   # the section, its top and its bottom
  at = rows_top
  for s in 0:length(sections)
    mine = findall(j -> j.section == s, tasks)
    isempty(mine) && continue
    foreach(((k, i),) -> row_y[i] = at + (k - 1) * row_h, enumerate(mine))
    tall = max(length(mine) * row_h, s == 0 ? 0.0 : heads[s].h + 0.7u)
    push!(bands, (s, at, at + tall))
    at += tall
  end
  bottom = at
  foot = isempty(marks) ? 0.0 : 1.7u    # the names of the lines down the chart are under it
  w = max(left + wide_chart + edge, heading.w + 2edge)
  h = bottom + foot + edge

  items = Any[]
  isempty(heading.lines) || write!(items, heading, w / 2, edge + heading.h / 2)
  x(t) = left + across(t)
  right = left + wide_chart
  # Every other section is a little darker, so that the eye can follow a row across
  for (k, (s, a, b)) in enumerate(bands)
    iseven(k) && push!(items, Shape(:plain, edge, a, right - edge, b - a; fill=(:text, 0.035), line=nothing))
    s == 0 || write_from!(items, heads[s], edge + 0.5u, (a + b) / 2, colour=:dim)
  end
  line(points, colour, thick=0.08u) = push!(items, Stroke(points; colour, thick))
  words(text, at, y; size=tiny, colour=:dim, bold=false, align=:left) = push!(items, Words(text, at, y, align, size, bold, false, colour))
  fits(text, room; kwargs...) = wide(pen, text; kwargs...) + 0.7u <= room
  if clock
    # The day is over the times, when the code gives one
    Dates.year(lo) > 1 && words("$(Dates.day(lo)) $(Dates.monthname(lo)) $(Dates.year(lo))", left + 0.4u, top + 1.0u, size=small, colour=:text, bold=true)
    t = lo
    while t <= hi
      line([(x(t), rows_top - 0.5u), (x(t), bottom)], (:text, 0.1))
      t < hi && words(Dates.format(t, "HH:MM"), x(t) + 0.3u, top + 2.55u)
      t += each
    end
  else
    day_w, month_w = step, 30.4step
    day = Date(lo)
    while DateTime(day) < hi
      at_x = x(DateTime(day))
      rests && off(day) && push!(items, Shape(:plain, at_x, rows_top, day_w, bottom - rows_top; fill=(:text, 0.05), line=nothing))
      new_month, monday = Dates.day(day) == 1, Dates.dayofweek(day) == 1
      if new_month && (month_w >= 1.2u || Dates.month(day) == 1)
        line([(at_x, top + 0.3u), (at_x, bottom)], (:text, 0.16))
      elseif each_day || (monday && each_week)
        line([(at_x, rows_top), (at_x, bottom)], (:text, monday ? 0.1 : 0.05))
      end
      if each_day
        words(string(Dates.day(day)), at_x + day_w / 2, top + 2.65u, align=:middle, colour=off(day) && rests ? (:dim, 0.55) : :dim)
      elseif monday && each_week && at_x + 3.3u <= right
        words("$(Dates.day(day)) $(Dates.monthabbr(day))", at_x + 0.35u, top + 2.65u)
      end
      day += Day(1)
    end
    # The name of each month is at its first day, or at the chart's left edge. Months that are too narrow for a name show only their years.
    by_year = month_w < 2.6u
    start = by_year ? Date(Dates.year(lo)) : Dates.firstdayofmonth(Date(lo))
    while DateTime(start) < hi
      next = start + (by_year ? Year(1) : Month(1))
      a, b = max(x(DateTime(start)), left), min(x(DateTime(next)), right)
      year = string(Dates.year(start))
      shown = by_year ? [year] : ["$(Dates.monthname(start)) $year", "$(Dates.monthabbr(start)) $year", Dates.monthabbr(start)]
      k = findfirst(text -> fits(text, b - a, size=small, bold=true), shown)
      k === nothing || words(shown[k], a + 0.4u, top + 1.0u, size=small, colour=:text, bold=true)
      start = next
    end
  end
  line([(left, rows_top), (right, rows_top)], :line)
  foreach(y -> line([(left, y), (right, y)], (:line, 0.5)), (row_y[i] + row_h for i in 1:length(tasks)))
  for j in marks
    at_x = x(j.from + (j.to - j.from) ÷ 2)
    line([(at_x, rows_top), (at_x, bottom + 0.3u)], :accent, 0.14u)
    l = label(pen, replace(j.name, '\n' => ' '), size=tiny)
    write!(items, l, clamp(at_x, edge + l.w / 2, w - edge - l.w / 2), bottom + 0.3u + foot / 2, colour=:dim)
  end
  for (i, j) in enumerate(tasks)
    (a, b), l, (where, at_x) = spans[i], names[i], places[i]
    y = row_y[i] + (row_h - bar_h) / 2
    middle = y + bar_h / 2
    # A task that's done is green and one that must not be late is red. One that's being done now is a stronger colour.
    hue = has(j, "done") ? 3 : has(j, "crit") ? 4 : :accent
    rim = has(j, "crit") ? 4 : hue
    if has(j, "milestone")
      push!(items, Shape(:diamond, left + a, middle - 0.65u, 1.3u, 1.3u; fill=hue, line=rim, thick=0.1u))
    else
      push!(items, Shape(:round, left + a, y, b - a, bar_h; fill=(hue, has(j, "active") ? 0.45 : 0.17), line=(rim, 0.9), thick=has(j, "crit") ? 0.14u : 0.08u))
      if has(j, "done") && b - a >= 1.5u
        line([(left + a + 0.42u, middle + 0.04u), (left + a + 0.66u, middle + 0.28u), (left + a + 1.05u, middle - 0.28u)], hue, 0.13u)
      end
    end
    where == :in ? write!(items, l, left + at_x, middle) : write_from!(items, l, left + at_x, middle)
  end
  Picture(w, h, items)
end

export gantt
