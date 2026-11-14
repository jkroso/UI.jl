@use Test: @test, @test_throws
@use "github.com/jkroso/MiniFB.jl" Window
@use "github.com/jkroso/Font.jl/units" px
@use "../../abstract" light dark with_theme describe SemanticUI
@use "../../Geometric"...
@use "../../draw" frame rect
@use "../../testing" pixels save_png
@use "./picture" Picture Problem Pen Shape Stroke Words Slice label plain statements styles paint
@use "./graph" Box Link arrange! spread
@use "./flowchart" flowchart read_chart read_link
@use "." Mermaid diagram problem kind

const pen = Pen("Helvetica", 13.0)
words(p::Picture) = [w.text for w in p.items if w isa Words]
shapes(p::Picture, kind) = [s for s in p.items if s isa Shape && s.kind == kind]
strokes(p::Picture) = [s for s in p.items if s isa Stroke]

# --- text -----------------------------------------------------------------------

@test plain("\"Some <b>bold</b> text<br/>on two lines\"") == "Some bold text\non two lines"
@test plain("fa:fa-car Car #quot;x#quot; #35;1") == "Car \"x\" #1"
@test styles("fill:#f9f,stroke:rgb(1,2,3),stroke-width:4px") == Dict("fill" => "#f9f", "stroke" => "rgb(1,2,3)", "stroke-width" => "4px")
@test paint("none") === nothing && paint("not a colour") === nothing && paint("#f00") !== nothing

# Comments, and the lines of --- at the top, aren't statements
let (lines, title) = statements("---\ntitle: A plan\n---\n%% a comment\nflowchart TD\n\n  A --> B %%{init: {}}%%\n")
  @test title == "A plan"
  @test lines == [(5, "flowchart TD"), (7, "A --> B")]
end

# A long label breaks between words, and a line of the text stays a line
let l = label(pen, "one two three four five six seven\nnext", most=80.0)
  @test length(l.lines) > 2 && l.lines[end] == "next"
  @test l.w <= 80
  @test l.h ≈ length(l.lines) * 1.35 * 13
end

# --- where boxes go ---------------------------------------------------------------

# Each box gets the place nearest the one it wants, in order, and no nearer its neighbour than it may be
@test spread([0.0, 0.0, 0.0], [1.0, 1.0, 1.0], [10.0, 10.0]) ≈ [-10.0, 0.0, 10.0]
@test spread([0.0, 50.0], [1.0, 1.0], [10.0]) ≈ [0.0, 50.0]

overlap(a::Box, b::Box) = abs(a.x - b.x) < (a.w + b.w) / 2 && abs(a.y - b.y) < (a.h + b.h) / 2

# A chain goes down in a straight line
let boxes = [Box(80, 40), Box(60, 40), Box(100, 40)], links = [Link(1, 2), Link(2, 3)]
  w, h = arrange!(boxes, links)
  @test boxes[1].y < boxes[2].y < boxes[3].y
  @test boxes[1].x ≈ boxes[2].x ≈ boxes[3].x
  @test w ≈ 100 && h ≈ 3 * 40 + 2 * 44
  # Each line goes from the bottom of a box to the top of the next
  @test links[1].path[1] == (boxes[1].x, boxes[1].y + 20) && links[1].path[end] == (boxes[2].x, boxes[2].y - 20)
end

# :LR goes across, and :BT and :RL are the other way round
let place(dir) = (boxes = [Box(80, 40), Box(80, 40)]; arrange!(boxes, [Link(1, 2)]; dir); boxes)
  a, b = place(:LR)
  @test a.x < b.x && a.y ≈ b.y
  a, b = place(:BT)
  @test a.y > b.y
  a, b = place(:RL)
  @test a.x > b.x
end

# A loop is laid out too, with one line turned round, and a label has room of its own
let boxes = [Box(80, 40) for _ in 1:4], links = [Link(1, 2), Link(2, 3, lw=60, lh=18), Link(3, 1), Link(1, 4), Link(4, 4)]
  arrange!(boxes, links)
  @test !any(overlap(boxes[i], boxes[j]) for i in 1:4 for j in i+1:4)
  @test all(l -> !isempty(l.path), links)
  @test boxes[2].y < links[2].ly < boxes[3].y
  @test boxes[3].y - boxes[2].y > boxes[2].y - boxes[1].y   # the label takes a row
end

# Two children sit either side of their parent, and many lines don't cross when they needn't
let boxes = [Box(80, 40) for _ in 1:7], links = [Link(1, 2), Link(1, 3), Link(2, 4), Link(2, 5), Link(3, 6), Link(3, 7)]
  arrange!(boxes, links)
  @test boxes[2].x < boxes[1].x < boxes[3].x
  @test boxes[4].x < boxes[5].x < boxes[6].x < boxes[7].x
  @test boxes[1].x ≈ (boxes[2].x + boxes[3].x) / 2
end

# A box that holds boxes is as big as they need, and they're in it
let boxes = [Box(0, 0, head=20.0), Box(80, 40, inside=1), Box(80, 40, inside=1), Box(80, 40)], links = [Link(2, 3), Link(3, 4)]
  arrange!(boxes, links, pad=10.0)
  group = boxes[1]
  @test group.w ≈ 100 && group.h ≈ 40 + 44 + 40 + 20 + 20
  @test all(b -> abs(b.x - group.x) <= group.w / 2 - b.w / 2 && abs(b.y - group.y) <= group.h / 2 - b.h / 2, boxes[2:3])
  @test boxes[4].y - 20 > group.y + group.h / 2
  # A line that leaves the group still starts at the box that it's from
  @test links[2].path[1] == (boxes[3].x, boxes[3].y + 20)
end

# --- flowcharts -------------------------------------------------------------------

let chart = read_chart("""
    flowchart LR
      A[Hard] -->|Link text| B(Round)
      B --> C{Choice}
      C -- One --> D([Pill]) & E[(Drum)]
      D -.-> F((Circle)); E ==> F
      F --- G{{Hex}} --o H[[Sub]] x--x I>Flag]
      J["A [bracket] in quotes"]:::loud
      a-b ---> K
    """)
  @test chart.dir == :LR
  @test [n.id for n in chart.nodes] == ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "a-b", "K"]
  @test [n.shape for n in chart.nodes[1:10]] == [:rect, :round, :diamond, :stadium, :cylinder, :circle, :hexagon, :subroutine, :flag, :rect]
  @test chart.nodes[10].text == "A [bracket] in quotes" && chart.nodes[10].classes == ["loud"]
  @test [(e.from, e.to) for e in chart.edges] == [("A", "B"), ("B", "C"), ("C", "D"), ("C", "E"), ("D", "F"), ("E", "F"),
                                                  ("F", "G"), ("G", "H"), ("H", "I"), ("a-b", "K")]
  @test [e.text for e in chart.edges[1:3]] == ["Link text", "", "One"]
  @test [e.kind for e in chart.edges[5:6]] == [:dotted, :thick]
  @test [(e.tail, e.head) for e in chart.edges[7:9]] == [(:none, :none), (:none, :circle), (:cross, :cross)]
  @test chart.edges[end].len == 2   # a longer arrow goes over more rows
end

# Each way to write a line
for (text, kind, tail, head, said) in [("-->", :solid, :none, :arrow, ""), ("---", :solid, :none, :none, ""), ("-.->", :dotted, :none, :arrow, ""),
                                       ("==>", :thick, :none, :arrow, ""), ("<-->", :solid, :arrow, :arrow, ""), ("--x", :solid, :none, :cross, ""),
                                       ("-- yes -->", :solid, :none, :arrow, "yes"), ("-. no .->", :dotted, :none, :arrow, "no"),
                                       ("== so ==>", :thick, :none, :arrow, "so"), ("-->|only if|", :solid, :none, :arrow, "only if"),
                                       ("~~~", :hidden, :none, :none, "")]
  edge, rest = read_link(text * " B")
  @test (edge.kind, edge.tail, edge.head, edge.text) == (kind, tail, head, said)
  @test strip(rest) == "B"
end

let p = flowchart("flowchart TD\n  A[Start] --> B{Is it done?}\n  B -- Yes --> C([Stop])\n  B -- No --> A", pen)
  @test p.w > 0 && p.h > 0
  @test sort(words(p)) == ["Is it done?", "No", "Start", "Stop", "Yes"]
  @test length(shapes(p, :diamond)) == 1 && length(shapes(p, :stadium)) == 1
  @test length(strokes(p)) == 3 && all(s -> s.to == :arrow && s.curved, strokes(p))
  # Nothing is outside the picture
  @test all(s -> s.x >= 0 && s.y >= 0 && s.x + s.w <= p.w && s.y + s.h <= p.h, [s for s in p.items if s isa Shape])
end

# A subgraph is a box around its boxes, and a line can end at it. A style gives a box its colours.
let p = flowchart("flowchart TB\n  subgraph one [The first]\n    a --> b\n  end\n  c --> one\n  style a fill:#f00,stroke:#00f\n  classDef big stroke-width:4px\n  class b big", pen)
  group = only(s for s in p.items if s isa Shape && s.fill == :group)
  inner = [s for s in p.items if s isa Shape && s.fill != :group]
  a, b, c = inner
  @test all(s -> group.x < s.x && s.x + s.w < group.x + group.w && group.y < s.y && s.y + s.h < group.y + group.h, (a, b))
  @test c.y + c.h < group.y
  @test "The first" in words(p)
  @test a.fill == paint("#f00") && a.line == paint("#00f")
  @test b.thick > 2a.thick
end

# What's wrong with the code, and where
@test_throws Problem flowchart("flowchart TD\n  A --> ", pen)
@test problem("flowchart TD\n  A[Open --> B") == "Line 2: The [ after A is never closed"
@test problem("flowchart TD\n  A --> B") === nothing
@test problem("gantt\n  title A plan") == "A `gantt` diagram can't be drawn yet"
@test problem("") == "A diagram starts with its kind, like `flowchart`"
@test kind("%% a note\n  stateDiagram-v2\n") == "stateDiagram"

# --- the other kinds ---------------------------------------------------------------

let p = diagram("""
    sequenceDiagram
      autonumber
      participant A as Alice
      actor B as Bob
      A->>+B: Hello
      B-->>-A: Hi
      Note over A,B: They talk
      loop Each day
        A-)B: Ping
      end
      B->>B: Think
    """)
  @test p isa Picture
  @test issubset(["Alice", "Bob", "Hello", "Hi", "They talk", "loop", "[Each day]", "Ping", "Think", "1", "4"], words(p))
  @test count(==("Alice"), words(p)) == 2   # at the top and at the bottom
  arrows = [s for s in strokes(p) if s.to != :none]
  @test [s.to for s in arrows] == [:arrow, :arrow, :open, :arrow]
  @test [s.dash for s in arrows] == [:solid, :dotted, :solid, :solid]
  # Each message is under the one before it
  @test issorted([s.points[1][2] for s in arrows])
  @test length([s for s in p.items if s isa Shape && s.fill == :bar && s.w < 12]) == 1   # the bar on Bob's line
  @test length([s for s in p.items if s isa Shape && s.fill == :note]) == 1
end
@test problem("sequenceDiagram\n  A->>B: Hi\n  end") == "Line 3: This `end` closes nothing"

let p = diagram("""
    stateDiagram-v2
      [*] --> Still
      Still --> Moving : push
      state Moving {
        [*] --> Slow
        Slow --> Fast
      }
      Moving --> [*]
      state "Out of fuel" as Empty
      Fast --> Empty
      note right of Still : It waits
    """)
  @test p isa Picture
  @test issubset(["Still", "Moving", "push", "Slow", "Fast", "Out of fuel", "It waits"], words(p))
  @test !("Empty" in words(p))
  @test length([s for s in p.items if s isa Shape && s.kind == :circle]) == 4   # two starts, and an end that's a ring and a dot
  @test length([s for s in strokes(p) if s.to == :arrow]) == 6
end
@test problem("stateDiagram-v2\n  state A {\n  B --> C") == "A { is never closed"

let p = diagram("""
    classDiagram
      class Animal {
        <<abstract>>
        +String name
        +eat(food) void
      }
      Animal <|-- Dog : is a
      Dog "1" *-- "4" Leg
      Dog ..> Bone
      Cat --o Toy
      Dog : +bark()
      class List~T~
    """)
  @test p isa Picture
  @test issubset(["Animal", "«abstract»", "+String name", "+eat(food) void", "Dog", "+bark()", "is a", "1", "4", "Leg", "Bone", "List<T>"], words(p))
  ends = [(s.from, s.to, s.dash) for s in strokes(p) if s.curved]
  @test ends == [(:triangle, :none, :solid), (:diamond, :none, :solid), (:none, :open, :dashed), (:none, :hollow, :solid)]
end

let p = diagram("pie showData title Pets\n  \"Dogs\" : 30\n  \"Cats\" : 10\n")
  @test p isa Picture
  slices = [s for s in p.items if s isa Slice]
  @test length(slices) == 2
  @test slices[1].from == 0 && slices[1].to ≈ 1.5pi && slices[2].to ≈ 2pi
  @test issubset(["Pets", "75%", "25%", "Dogs  (30)", "Cats  (10)"], words(p))
end
@test problem("pie\n  Dogs : 3") == "Line 2: A slice is a name in quotes, a colon and a number"

# --- the component ----------------------------------------------------------------

# It's as big as its picture, and in less room it's drawn smaller, in proportion
let code = "flowchart LR\n  A[One box] --> B[Another box] --> C[A third box] --> D[The last box]", m = Mermaid(code)
  w = Window(Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, m), size=(900px, 300px))
  frame(w)
  natural = m.made[2]::Picture
  @test rect(m).width.value ≈ natural.w && rect(m).height.value ≈ natural.h
  m = Mermaid(code)
  narrow = Window(Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, m), size=(300px, 300px))
  frame(narrow)
  @test rect(m).width == 300px
  @test rect(m).height.value ≈ 300 * natural.h / natural.w
end

# Each kind draws something in each theme, and code that can't be read shows a sentence
for code in ("flowchart TD\n  A --> B{C}\n  B -->|x| D((E))", "sequenceDiagram\n  A->>B: Hi", "stateDiagram-v2\n  [*] --> A",
             "classDiagram\n  A <|-- B", "pie\n  \"a\" : 1\n  \"b\" : 2", "flowchart TD\n  A -->")
  for theme in (light, dark)
    m = Mermaid(code)
    w = Window(Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, padding(8px), background(theme.surface),
                      with_theme(() -> m, theme)), size=(400px, 300px))
    frame(w)
    @test rect(m) !== nothing && rect(m).height > 0px
    picture = joinpath(mktempdir(), "diagram.png")
    save_png(picture, w)
    @test length(unique(pixels(picture))) > 2   # more than its background
  end
end
