# Tests for the kinds of diagram that can't be changed where they're drawn: a
# mind map, an entity relationship diagram, a Gantt chart and a timeline. Set
# the environment variable MERMAID_SHOTS to a folder to keep a picture of each
# kind, in the light theme, in the dark one, and in a narrow window.

@use Test: @test, @test_throws
@use "github.com/jkroso/MiniFB.jl" Window KeyPress Keys onkey
@use "github.com/jkroso/Font.jl/units" px
@use "github.com/jkroso/Prospects.jl" @def
@use "../../abstract" SemanticUI describe light dark with_theme
@use "../../Geometric"...
@use "../../draw" frame rect
@use "../../testing" pixels save_png click!
@use "./picture" Picture Problem Pen Shape Stroke Words
@use "./mindmap" read_ideas right_side
@use "./er" read_entities
@use "./gantt" read_gantt moment stretched later
@use "./timeline" read_timeline
@use Dates: Dates, Date, DateTime, Day
@use "." Mermaid diagram problem kind tools pick_at! key! changes

const pen = Pen("Helvetica", 13.0)
words(p::Picture) = [w.text for w in p.items if w isa Words]
shapes(p::Picture, kind) = [s for s in p.items if s isa Shape && s.kind == kind]
strokes(p::Picture) = [s for s in p.items if s isa Stroke]
"The shape of the picture that has `text` in its middle"
around(p::Picture, text) = begin
  w = only(w for w in p.items if w isa Words && w.text == text)
  only(s for s in p.items if s isa Shape && s.x <= w.x <= s.x + s.w && s.y <= w.y <= s.y + s.h)
end
"True when everything in the picture is inside its edges"
inside(p::Picture) = all(p.items) do item
  item isa Shape ? item.x >= 0 && item.y >= 0 && item.x + item.w <= p.w + 0.01 && item.y + item.h <= p.h + 0.01 :
  item isa Stroke ? all(q -> -0.01 <= q[1] <= p.w + 0.01 && -0.01 <= q[2] <= p.h + 0.01, item.points) :
  item isa Words ? 0 <= item.x <= p.w && 0 <= item.y <= p.h : true
end

const shots = get(ENV, "MERMAID_SHOTS", "")

"A page in the light theme or the dark one, with a diagram on it"
@def mutable struct Page <: SemanticUI
  look::Any = light
end
describe(p::Page) = with_theme(p.look) do
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, padding(10px), background(p.look.surface), p.children...)
end

"""
Draw the diagram `code` in a window that isn't on the screen: in the light
theme, in the dark one and in a narrow window. Each must show more than its
background, and a click or a key on it does nothing.
"""
shown(name, code) = begin
  for (theme, look, wide) in ((light, "light", 760px), (dark, "dark", 760px), (light, "narrow", 300px))
    m = Mermaid(code, editing=true)
    page = Page(m)
    page.look = theme
    w = Window(page, size=(wide, 1200px))
    frame(w)
    made = m.made[2]
    @test made isa Picture
    @test rect(m).width.value <= wide.value - 20 + 0.01 && rect(m).width.value <= made.w + 0.01
    @test rect(m).height.value ≈ rect(m).width.value * made.h / made.w
    file = joinpath(isempty(shots) ? mktempdir() : shots, "$name-$look.png")
    save_png(file, w)
    @test length(unique(pixels(file))) > 2
    # It has no parts to select, so a click or a key on it changes nothing and throws nothing
    @test !changes(m) && isempty(tools(m))
    click!(w, m)
    onkey(w, KeyPress{Keys.enter}(0, w))
    onkey(w, KeyPress{Keys.backspace}(0, w))
    frame(w)
    @test !pick_at!(m, made.w / 2, made.h / 2) && !key!(m, Keys.enter) && m.picked === nothing && m.typing === nothing
  end
end

# --- mind maps --------------------------------------------------------------------

const MINDMAP = """
mindmap
  root((Ladder))
    Pages
      Diagrams
      ::icon(fa fa-book)
        Flowcharts
        Mind maps
      Tables
    Sharing
      [A page of HTML]
      (A printed page)
      {{A link}}
    Agents
    :::urgent large
      ))They write pages((
      )They read what you change(
"""

@test kind(MINDMAP) == "mindmap"

let (ideas, title) = read_ideas(MINDMAP)
  @test [i.text for i in ideas] == ["Ladder", "Pages", "Diagrams", "Flowcharts", "Mind maps", "Tables", "Sharing", "A page of HTML",
                                    "A printed page", "A link", "Agents", "They write pages", "They read what you change"]
  @test [i.shape for i in ideas] == [:circle, :default, :default, :default, :default, :default, :default, :rect, :round, :hexagon,
                                     :default, :hexagon, :stadium]
  @test [i.parent for i in ideas] == [0, 1, 2, 3, 3, 2, 1, 7, 7, 7, 1, 11, 11]
  @test [i.depth for i in ideas] == [0, 1, 2, 3, 3, 2, 1, 2, 2, 2, 1, 2, 2]
  @test [i.branch for i in ideas] == [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3]
  @test ideas[1].children == [2, 7, 11]
end

# A line that isn't as far in as the one above it belongs to the nearest line above that starts further left
let (ideas, _) = read_ideas("mindmap\nRoot\n    A\n        B\n      C\n")
  @test [i.parent for i in ideas] == [0, 1, 2, 2]
end

# A name before the signs isn't shown, words can be in quotes, and words in "` `" can go on over lines
let (ideas, _) = read_ideas("mindmap\n  id1[\"`**Root** with\na second line`\"]\n    id2[\"A [box] in quotes\"]\n    Two<br/>lines\n")
  @test [i.text for i in ideas] == ["Root with\na second line", "A [box] in quotes", "Two\nlines"]
  @test [i.shape for i in ideas] == [:rect, :rect, :default]
end

# The two sides are as near as can be to the same height
@test right_side(Float64[]) == 0 && right_side([10.0]) == 1 && right_side([10.0, 10.0]) == 1
@test right_side([10.0, 10.0, 10.0]) == 2 && right_side([50.0, 10.0, 10.0, 10.0]) == 1

let p = diagram(MINDMAP)
  @test p isa Picture && p.w > 0 && p.h > 0
  @test inside(p)
  @test issubset(["Ladder", "Pages", "Flowcharts", "A page of HTML", "They write pages"], words(p))
  root = around(p, "Ladder")
  @test root.kind == :circle && root.fill == :accent
  # The middle idea is in the middle, with ideas of its own on both sides
  heads = [around(p, t) for t in ("Pages", "Sharing", "Agents")]
  @test heads[1].x > root.x + root.w && heads[2].x + heads[2].w < root.x && heads[3].x + heads[3].w < root.x
  @test heads[2].y + heads[2].h < heads[3].y   # one under the other, in the order of the code
  # Each has a colour of its own, which its line and the ideas under it have too
  @test [h.fill for h in heads] == [1, 2, 3]
  @test around(p, "A page of HTML").kind == :rect && around(p, "A page of HTML").line == 2 && around(p, "A page of HTML").fill == (2, 0.16)
  @test around(p, "A printed page").kind == :round && around(p, "A link").kind == :hexagon
  @test around(p, "They read what you change").kind == :stadium && around(p, "They read what you change").line == 3
  # An idea is joined to the one that it belongs to: one line for each idea but the middle one
  joins = [s for s in strokes(p) if s.curved]
  @test length(joins) == 12
  @test count(s -> s.colour == 1, joins) == 5 && count(s -> s.colour == 3, joins) == 3
  # Words alone, further out, are on a line of their colour, and their line from the idea before meets it
  tables = only(w for w in p.items if w isa Words && w.text == "Tables")
  under = only(s for s in strokes(p) if !s.curved && s.colour == 1 && s.points[1][1] <= tables.x <= s.points[2][1] && 0 < s.points[1][2] - tables.y < 15)
  @test any(s -> all(isapprox.(s.points[end], under.points[1]; atol=1e-6)), joins)
  # No two ideas are on top of each other
  boxes = [s for s in p.items if s isa Shape]
  @test !any(a !== b && a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h for a in boxes for b in boxes)
end

# A mind map with only its middle, and one with nothing, which draws nothing
@test words(diagram("mindmap\n  Alone")) == ["Alone"]
let p = diagram("mindmap\n")
  @test p isa Picture && p.w == 0
end
# The title that the top of the code gives is over the map
@test "A plan" in words(diagram("---\ntitle: A plan\n---\nmindmap\n  Root\n    A"))
# A second idea that belongs to nothing can't be drawn
@test problem("mindmap\n  Root\n    A\n  Other") == "Line 4: Only the first idea can start this far left. The others belong to it."

shown("mindmap", MINDMAP)

# --- entity relationship diagrams ---------------------------------------------------

const ER = """
erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER ||--|{ LINE-ITEM : contains
  CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
  PRODUCT |o--o| LINE-ITEM : "is on"
  CUSTOMER {
    int id PK
    string name
    string email UK "Where the bill goes"
  }
  ORDER {
    int id PK
    int customer FK
    date placed
  }
  LINE-ITEM {
    int order PK, FK
    string(12) *code
    float price
  }
  p[Person]
  p ||--|| CUSTOMER : is
"""

@test kind(ER) == "erDiagram"

let r = read_entities(ER)
  @test [e.id for e in r.entities] == ["CUSTOMER", "ORDER", "LINE-ITEM", "DELIVERY-ADDRESS", "PRODUCT", "p"]
  @test r.entities[end].name == "Person"
  @test r.entities[1].rows == [("int", "id", "PK", ""), ("string", "name", "", ""), ("string", "email", "UK", "Where the bill goes")]
  @test r.entities[3].rows == [("int", "order", "PK, FK", ""), ("string(12)", "code", "PK", ""), ("float", "price", "", "")]
  @test isempty(r.entities[4].rows)
  @test [(x.from, x.to, x.left, x.right, x.dotted, x.text) for x in r.relationships] ==
        [("CUSTOMER", "ORDER", :one, :zero_or_more, false, "places"), ("ORDER", "LINE-ITEM", :one, :one_or_more, false, "contains"),
         ("CUSTOMER", "DELIVERY-ADDRESS", :one_or_more, :one_or_more, true, "uses"), ("PRODUCT", "LINE-ITEM", :zero_or_one, :zero_or_one, false, "is on"),
         ("p", "CUSTOMER", :one, :one, false, "is")]
end

# Every sign for how many, at either end, with and without spaces, and the words that mean the same
for (text, left, right, dotted) in [("A ||--|| B", :one, :one, false), ("A |o--o| B", :zero_or_one, :zero_or_one, false),
                                    ("A }o--o{ B", :zero_or_more, :zero_or_more, false), ("A }|--|{ B", :one_or_more, :one_or_more, false),
                                    ("A }o..|| B : x", :zero_or_more, :one, true), ("A||--o{B", :one, :zero_or_more, false),
                                    ("A only one to zero or more B : makes", :one, :zero_or_more, false),
                                    ("A many(0) optionally to 0+ B", :zero_or_more, :zero_or_more, true),
                                    ("A 1 to 1+ B", :one, :one_or_more, false), ("\"A b\" one or zero to one or many B", :zero_or_one, :one_or_more, false)]
  r = read_entities("erDiagram\n  " * text)
  x = only(r.relationships)
  @test (x.left, x.right, x.dotted) == (left, right, dotted)
  @test [e.id for e in r.entities] == [startswith(text, '"') ? "A b" : "A", "B"]
end

# An entity by itself, one with a class, and the way that the diagram goes
let r = read_entities("erDiagram\n  direction LR\n  ALONE\n  CAR:::loud {\n    string make\n  }\n  classDef loud fill:#f96\n  style ALONE stroke:#00f\n  subgraph Yard\n    CAR ||--o{ WHEEL : has\n  end")
  @test r.dir == :LR && [e.id for e in r.entities] == ["ALONE", "CAR", "WHEEL"]
  @test r.entities[2].classes == ["loud"] && r.styles_of["loud"] == Dict("fill" => "#f96") && r.entities[1].style == Dict("stroke" => "#00f")
end

let p = diagram(ER)
  @test p isa Picture && p.w > 0 && p.h > 0
  @test inside(p)
  @test issubset(["CUSTOMER", "ORDER", "LINE-ITEM", "DELIVERY-ADDRESS", "PRODUCT", "Person", "places", "contains", "uses", "is on",
                  "int", "email", "UK", "PK, FK", "Where the bill goes", "string(12)", "code"], words(p))
  @test !("p" in words(p))
  boxes = shapes(p, :rect)
  @test length(boxes) == 6
  @test !any(a !== b && a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h for a in boxes for b in boxes)
  # Each line between two entities starts and ends on the edge of a box, and one is dashed
  lines = [s for s in strokes(p) if s.curved]
  @test length(lines) == 5 && count(s -> s.dash == :dashed, lines) == 1
  on_edge(q) = any(b -> (b.x - 0.01 <= q[1] <= b.x + b.w + 0.01 && b.y - 0.01 <= q[2] <= b.y + b.h + 0.01) &&
                        (min(abs(q[1] - b.x), abs(q[1] - b.x - b.w), abs(q[2] - b.y), abs(q[2] - b.y - b.h)) < 0.01), boxes)
  @test all(s -> on_edge(s.points[1]) && on_edge(s.points[end]), lines)
  # The ends: a ring for each "none", and the toes of each "many" meet the box at the end of the line
  rings = shapes(p, :circle)
  @test length(rings) == 3 && all(r -> r.fill == :surface, rings)
  toes = [s for s in strokes(p) if !s.curved && s.colour == :link && any(l -> any(e -> hypot(s.points[2][1] - e[1], s.points[2][2] - e[2]) < 0.45 * 13 + 0.01, (l.points[1], l.points[end])), lines) &&
          s.points[1] != s.points[2] && hypot(s.points[1][1] - s.points[2][1], s.points[1][2] - s.points[2][2]) > 0.9 * 13]
  @test length(toes) == 2 * 4   # two toes beside the line, at each of the four ends that are many
end

# A line from an entity to itself is inside the picture
@test inside(diagram("erDiagram\n  PERSON ||--o{ PERSON : manages\n  PERSON {\n    string name\n  }"))
# An entity with nothing in it and nothing else draws its name
@test words(diagram("erDiagram\n  ALONE")) == ["ALONE"]
@test diagram("erDiagram\n").w == 0
@test problem("erDiagram\n  A ||--o{ B : has\n  A => B") == "Line 3: \"A => B\" isn't an entity or a line between two entities"
@test problem("erDiagram\n  A {\n    name\n  }") == "Line 3: A row of an entity is a type and a name, like `string name`"
@test problem("erDiagram\n  A {\n    string name") == "The { of the entity A is never closed"

shown("er", ER)

# --- Gantt charts -------------------------------------------------------------------

const GANTT = """
gantt
  title A page for the shop
  dateFormat YYYY-MM-DD
  excludes weekends
  section Design
    Draw the page      :done, draw, 2024-03-04, 3d
    Ask the owner      :active, ask, after draw, 2d
  section Build
    Write the code     :crit, code, after ask, 5d
    Write the words    :words, 2024-03-11, 2024-03-14
    Test it            :after code words, 2d
    Open the shop      :milestone, open, 2024-03-22, 0d
  section After
    Watch the orders   :until last
    Last look          :last, 2024-04-08, 1d
"""

@test kind(GANTT) == "gantt"

# Dates as the code says they're written
@test moment("2024-03-04", "YYYY-MM-DD") == DateTime(2024, 3, 4)
@test moment("4/3/24", "D/M/YY") == DateTime(2024, 3, 4)
@test moment("04.03.2024 17:49", "DD.MM.YYYY HH:mm") == DateTime(2024, 3, 4, 17, 49)
@test moment("17:49", "HH:mm") == DateTime(1, 1, 1, 17, 49)
@test moment("4 March 2024", "D MMMM YYYY") == DateTime(2024, 3, 4)
@test moment("soon", "YYYY-MM-DD") === nothing && moment("2024-13-40", "YYYY-MM-DD") === nothing

# A length, from a time
@test later(DateTime(2024, 1, 31), (1.0, "d")) == DateTime(2024, 2, 1) && later(DateTime(2024, 1, 1), (2.0, "w")) == DateTime(2024, 1, 15)
@test later(DateTime(2024, 1, 1), (36.0, "h")) == DateTime(2024, 1, 2, 12) && later(DateTime(2024, 1, 15), (1.0, "M")) == DateTime(2024, 2, 15)
@test later(DateTime(2024, 1, 1), (1.5, "d")) == DateTime(2024, 1, 2, 12) && later(DateTime(2024, 1, 1), (1.0, "y")) == DateTime(2025, 1, 1)

# A task that goes over a weekend ends two days later. One that ends at a weekend has its bar end there, and the next task starts on Monday.
let weekend(d) = Dates.dayofweek(d) > 5
  @test stretched(DateTime(2024, 3, 7), DateTime(2024, 3, 10), weekend) == (DateTime(2024, 3, 12), DateTime(2024, 3, 12))   # Thursday, 3 days
  @test stretched(DateTime(2024, 3, 8), DateTime(2024, 3, 9), weekend) == (DateTime(2024, 3, 11), DateTime(2024, 3, 9))     # Friday, 1 day
  @test stretched(DateTime(2024, 3, 4), DateTime(2024, 3, 7), weekend) == (DateTime(2024, 3, 7), DateTime(2024, 3, 7))      # Monday, 3 days
end

let g = read_gantt(GANTT), day(d) = DateTime(2024, 3, d)
  @test g.title == "A page for the shop" && g.sections == ["Design", "Build", "After"] && g.rests
  @test [j.name for j in g.jobs] == ["Draw the page", "Ask the owner", "Write the code", "Write the words", "Test it", "Open the shop", "Watch the orders", "Last look"]
  @test [j.id for j in g.jobs] == ["draw", "ask", "code", "words", "task5", "open", "task7", "last"]
  @test [j.section for j in g.jobs] == [1, 1, 2, 2, 2, 2, 3, 3]
  @test [j.marks for j in g.jobs[1:3]] == [["done"], ["active"], ["crit"]] && g.jobs[6].marks == ["milestone"]
  # Monday the 4th, 3 days. Then 2 days: Thursday and Friday. The code starts on the Monday after, and takes 5 days.
  @test [(j.from, j.to) for j in g.jobs[1:3]] == [(day(4), day(7)), (day(7), day(9)), (day(11), day(16))]
  @test g.jobs[3].next == day(18)
  # Dates for both ends, as they're written
  @test (g.jobs[4].from, g.jobs[4].to) == (day(11), day(14))
  # After the later of two tasks, and with no start: after the task above
  @test (g.jobs[5].from, g.jobs[5].to) == (day(18), day(20))
  @test (g.jobs[6].from, g.jobs[6].to) == (day(22), day(22))
  # Until a task that's further down starts
  @test (g.jobs[7].from, g.jobs[7].to) == (day(22), DateTime(2024, 4, 8))
  @test g.off(Date(2024, 3, 9)) && g.off(Date(2024, 3, 10)) && !g.off(Date(2024, 3, 11))
end

# The days that are left out: a day of the week, a date, a weekend that starts on Friday, and a date that work is done on all the same
let g = read_gantt("gantt\n  dateFormat DD-MM-YYYY\n  excludes weekends, monday 06-03-2024\n  weekend friday\n  includes 08-03-2024\n  A :a, 04-03-2024, 1d\n  B :2d")
  @test g.off(Date(2024, 3, 4)) && g.off(Date(2024, 3, 6)) && g.off(Date(2024, 3, 9)) && !g.off(Date(2024, 3, 8)) && !g.off(Date(2024, 3, 10))
  # A starts on a Monday. The day that a task starts on counts, though it's left out, as it does in Mermaid.
  @test (g.jobs[1].from, g.jobs[1].next) == (DateTime(2024, 3, 4), DateTime(2024, 3, 5))
  # B is Tuesday and Thursday: Wednesday the 6th is left out
  @test (g.jobs[2].from, g.jobs[2].next) == (DateTime(2024, 3, 5), DateTime(2024, 3, 8))
end
# A first task with no start begins today, and an end that's a date can be its last day
let g = read_gantt("gantt\n  inclusiveEndDates\n  A :3d\n  B :b, 2024-03-04, 2024-03-06"; today=Date(2024, 5, 1))
  @test (g.jobs[1].from, g.jobs[1].to) == (DateTime(2024, 5, 1), DateTime(2024, 5, 4))
  @test g.jobs[2].to == DateTime(2024, 3, 7) && !g.rests
end

let p = diagram(GANTT)
  @test p isa Picture && p.w > 0 && p.h > 0
  @test inside(p)
  @test issubset(["A page for the shop", "Design", "Build", "After", "Draw the page", "Open the shop", "March 2024", "April 2024", "4 Mar", "1 Apr"], words(p))
  bars = shapes(p, :round)
  @test length(bars) == 7 && length(shapes(p, :diamond)) == 1
  # The bars are in the order of the code, one row each, and a day is as wide for each
  @test issorted([b.y for b in bars]) && allunique([b.y for b in bars])
  @test bars[1].w / 3 ≈ bars[2].w / 2 ≈ bars[3].w / 5
  @test bars[2].x ≈ bars[1].x + bars[1].w && bars[3].x ≈ bars[2].x + 2 * bars[2].w   # Monday comes two days after Friday ends
  # What each mark does: done is green, crit is red, and active is a stronger colour
  @test bars[1].fill == (3, 0.17) && bars[2].fill == (:accent, 0.45) && bars[3].fill == (4, 0.17) && bars[3].line == (4, 0.9) && bars[4].fill == (:accent, 0.17)
  # The milestone is at its day
  stone = only(shapes(p, :diamond))
  @test stone.x + stone.w / 2 ≈ bars[1].x + 18 * bars[1].w / 3
  # Saturdays and Sundays are shaded: 5 weekends are in sight
  @test count(s -> s.fill == (:text, 0.05), shapes(p, :plain)) == 10
end

# A chart of a few days has the number of each day over it
@test issubset(["March 2024", "4", "5", "6", "Short"], words(diagram("gantt\n  Short :a, 2024-03-04, 3d")))
# A chart of minutes shows times, and a chart of years shows the years
let p = diagram("gantt\n  dateFormat HH:mm\n  First :milestone, m1, 17:49, 2m\n  Task A :10m\n  Task B :5m\n  Mark :vert, v, 17:55, 0m")
  @test p isa Picture && inside(p)
  @test issubset(["17:50", "18:00", "Task A", "Mark"], words(p)) && !any(w -> occursin("0001", w) || occursin("January", w), words(p))
end
let p = diagram("gantt\n  Long :a, 2020-02-01, 3y\n  Longer :after a, 30M")
  @test p isa Picture && inside(p) && p.w < 60 * 13
  @test issubset(["2021", "2022", "2023", "2024"], words(p))
end
@test diagram("gantt\n  title Nothing yet").w == 0

@test problem("gantt\n  A :a, 2024-03-04, 3d\n  Just some words") == "Line 3: A task is its name, a colon and its days, like `Write it :2024-03-04, 3d`"
@test problem("gantt\n  A :a, 04/03/2024, 3d") == "Line 2: \"04/03/2024\" isn't a date like YYYY-MM-DD, or `after` and the id of a task"
@test problem("gantt\n  A :a, 2024-03-04, soon") == "Line 2: \"soon\" isn't a length like `3d`, a date like YYYY-MM-DD, or `until` and the id of a task"
@test problem("gantt\n  A :after b, 3d") == "Line 2: No task has the id `b`"
@test problem("gantt\n  A :a, after b, 3d\n  B :b, after a, 1d") == "Line 2: This task waits for a task that waits for it"
@test problem("gantt\n  A :done") == "Line 2: A task needs a length or an end after its colon, like `3d`"
@test problem("gantt\n  excludes weekends\n  A :a, 2024-03-04, 99999999d") == "Line 3: This task is longer than 200 years"
@test problem("gantt\n  A :a, 1700-01-01, 1d\n  B :b, 2024-03-04, 1d") == "The chart is longer than 200 years"
@test problem("gantt\n  excludes someday\n  A :1d") == "Line 2: \"someday\" isn't `weekends`, a day of the week or a date like YYYY-MM-DD"

shown("gantt", GANTT)
shown("gantt-clock", "gantt\n  title One evening\n  dateFormat YYYY-MM-DD HH:mm\n  section Kitchen\n  Chop :done, chop, 2024-03-04 17:45, 20m\n  Cook :active, cook, after chop, 45m\n  Serve :milestone, after cook, 0m\n  section Table\n  Lay the table :crit, 2024-03-04 18:20, 15m\n  Guests arrive :vert, 2024-03-04 18:40, 0m")
shown("gantt-years", "gantt\n  title A long job\n  section One\n  Plan it :done, a, 2020-02-01, 1y\n  Build it :active, b, after a, 30M\n  section Two\n  Use it :after b, 2y")

# --- timelines ----------------------------------------------------------------------

const TIMELINE = """
timeline
  title How the app grew
  section The first year
    2023 : Pages of Markdown : Tables
    2024 : Diagrams
         : Sums that add up as you type, in a sheet
  section Now
    2025 : Boards and charts
    Later
"""

@test kind(TIMELINE) == "timeline"

let t = read_timeline(TIMELINE)
  @test t.title == "How the app grew" && t.sections == ["The first year", "Now"]
  @test [p.text for p in t.periods] == ["2023", "2024", "2025", "Later"]
  @test [p.events for p in t.periods] == [["Pages of Markdown", "Tables"], ["Diagrams", "Sums that add up as you type, in a sheet"], ["Boards and charts"], String[]]
  @test [p.section for p in t.periods] == [1, 1, 2, 2]
end
# A colon in a time parts nothing, and <br> starts a new line
let t = read_timeline("timeline TD\n  9:30 : Wake<br>up : Coffee at 10:15\n  Noon:Lunch")
  @test [(p.text, p.events) for p in t.periods] == [("9:30", ["Wake\nup", "Coffee at 10:15"]), ("Noon", ["Lunch"])]
  @test all(p -> p.section == 0, t.periods)
end

let p = diagram(TIMELINE)
  @test p isa Picture && p.w > 0 && p.h > 0
  @test inside(p)
  @test issubset(["How the app grew", "The first year", "Now", "2023", "2024", "2025", "Later", "Pages of Markdown", "Tables", "Diagrams", "Boards and charts"], words(p))
  periods = [around(p, t) for t in ("2023", "2024", "2025", "Later")]
  # The periods go from left to right, in a row, each as wide as the next
  @test issorted([b.x for b in periods]) && allunique([b.x for b in periods])
  @test all(b -> b.y == periods[1].y && b.w == periods[1].w && b.h == periods[1].h, periods)
  # A section is over its periods, and they share its colour
  first, now = [only(s for s in shapes(p, :round) if s.fill == k && s.line === nothing) for k in 1:2]
  @test first.x ≈ periods[1].x && first.x + first.w ≈ periods[2].x + periods[2].w && first.y + first.h < periods[1].y
  @test now.x ≈ periods[3].x && now.x + now.w ≈ periods[4].x + periods[4].w
  @test [b.fill for b in periods] == [(1, 0.4), (1, 0.4), (2, 0.4), (2, 0.4)]
  # The events of a period are under it, one under the other, in the order of the code
  one, two = around(p, "Pages of Markdown"), around(p, "Tables")
  @test one.x ≈ periods[1].x && two.x ≈ periods[1].x && periods[1].y + periods[1].h < one.y && one.y + one.h < two.y
  @test one.fill == (1, 0.16) && around(p, "Boards and charts").fill == (2, 0.16)
  # The line of time goes under the periods and over the events, past the last period, with an arrow
  line = only(s for s in strokes(p) if s.to == :arrow)
  @test periods[1].y + periods[1].h < line.points[1][2] < one.y
  @test line.points[1][1] <= periods[1].x && line.points[2][1] > periods[4].x + periods[4].w
  # Words that are too long for a period's width go on to another line
  @test count(w -> occursin("Sums", w) || occursin("sheet", w), words(p)) == 2
end

# Without sections, each period has its own colour
let p = diagram("timeline\n  2002 : LinkedIn\n  2004 : Facebook : Google\n  2005 : YouTube")
  @test [around(p, t).fill for t in ("2002", "2004", "2005")] == [1, 2, 3]
  @test around(p, "Google").fill == (2, 0.16)
end
@test diagram("timeline\n  title Nothing yet").w == 0
@test problem("timeline\n  : An event with no period") == "Line 2: An event needs a period before its colon, like `2024 : What happened`"

shown("timeline", TIMELINE)
