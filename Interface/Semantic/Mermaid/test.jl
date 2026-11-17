@use Test: @test, @test_throws
@use "github.com/jkroso/MiniFB.jl" Window
@use "github.com/jkroso/Font.jl/units" px
@use "../../abstract" light dark with_theme describe SemanticUI
@use "../../Geometric"...
@use "../../draw" frame rect
@use "../../testing" pixels save_png click! move!
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" KeyPress KeyRelease Keys Typed onkey ontype
@use "./picture" Picture Problem Pen Shape Stroke Words Slice Part Tool label plain statements styles paint added relined quoted wide
@use "./graph" Box Link arrange! spread
@use "./flowchart" flowchart read_chart read_link flowchart_edits
@use "./pie" pie_edits
@use "./state" state_edits
@use "./sequence" sequence_edits
@use "./class" class_edits
@use "." Mermaid diagram problem kind tools use! pick_at! key! retype! settle! cancel! part part_at pictured point_of landing ToolButton

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

# --- changing a flowchart ----------------------------------------------------------

# Words that mean something to the code go in quotes, and a new line of code starts as far in as the others
@test quoted("Is it clear?") == "Is it clear?" && quoted("a [b]") == "\"a [b]\"" && quoted("say \"hi\"") == "\"say #quot;hi#quot;\""
@test added("flowchart TD\n    A --> B\n\n", "B --> C") == "flowchart TD\n    A --> B\n    B --> C\n\n"
@test added("flowchart TD", "A") == "flowchart TD\n  A"
@test relined("a\n  b\nc", Dict(2 => ["x", "y"], 3 => String[])) == "a\n  x\n  y"

let code = "flowchart LR\n  %% a note\n  A[Write a page] --> B{Is it clear?}\n  B -- Yes --> C([Share it])\n  B -- No --> D[Change it]\n  D --> B\n  style D fill:#f00",
    (; said, reword, tools, use) = flowchart_edits
  p = flowchart(code, pen)
  # Each box and each line is a part, with the boxes first
  @test [(x.kind, x.key) for x in p.parts] == [(:box, "A"), (:box, "B"), (:box, "C"), (:box, "D"), (:line, 1), (:line, 2), (:line, 3), (:line, 4)]
  @test p.parts[2].shape == :diamond && length(p.parts[5].path) > 2
  @test said(code, :box, "B") == "Is it clear?" && said(code, :line, 2) == "Yes" && said(code, :line, 1) == ""

  # New words go where the old ones were, and the rest of the code stays as it was written
  @test reword(code, :box, "A", "Draft it") == replace(code, "A[Write a page]" => "A[Draft it]")
  @test reword(code, :box, "B", "Good (enough)?") == replace(code, "B{Is it clear?}" => "B{\"Good (enough)?\"}")
  @test reword(code, :line, 2, "Sure") == replace(code, "B -- Yes --> C" => "B -->|Sure| C")
  @test reword(code, :line, 1, "then") == replace(code, "A[Write a page] --> B" => "A[Write a page] -->|then| B")
  @test reword(code, :line, 3, "") == replace(code, "B -- No --> D" => "B --> D")
  # A box that the code only names gets its words after its name
  @test reword("flowchart TD\n  A --> B", :box, "B", "End") == "flowchart TD\n  A --> B[End]"
  @test said(reword(code, :box, "A", "One<br>two"), :box, "A") == "One<br>two"

  # A new box goes after the one that's selected, and its words are typed next
  new, picked, typing = use(code, :add, :box, "C", nothing)
  @test new == code * "\n  C --> E[New box]" && picked == (:box, "E") && typing
  @test use(code, :add, :none, nothing, nothing)[1] == code * "\n  E[New box]"
  new, picked, typing = use(code, :join, :box, "C", (:box, "A"))
  @test new == code * "\n  C --> A" && picked == (:line, 5) && !typing
  @test use(code, :join, :box, "C", nothing)[1] == code

  @test use(code, :shape, :box, "D", :stadium)[1] == replace(code, "D[Change it]" => "D([Change it])")
  @test use("flowchart TD\n  A --> B", :shape, :box, "A", :diamond)[1] == "flowchart TD\n  A{A} --> B"
  @test use(code, :look, :line, 3, (:dotted, :none, :arrow))[1] == replace(code, "B -- No --> D" => "B -.->|No| D")
  @test use(code, :look, :line, 4, (:solid, :none, :none))[1] == replace(code, "D --> B" => "D --- B")
  @test use(code, :turn, :line, 4, nothing)[1] == replace(code, "D --> B" => "B --> D")
  @test use(code, :way, :none, nothing, "TD")[1] == replace(code, "flowchart LR" => "flowchart TD")

  # A line goes, and its boxes stay
  less = use(code, :delete, :line, 4, nothing)[1]
  @test less == replace(code, "\n  D --> B" => "")
  @test use(code, :delete, :line, 2, nothing)[1] == replace(code, "B -- Yes --> C([Share it])" => "C([Share it])")
  # A box goes with its lines and its style
  less = use(code, :delete, :box, "D", nothing)[1]
  @test less == "flowchart LR\n  %% a note\n  A[Write a page] --> B{Is it clear?}\n  B -- Yes --> C([Share it])"
  @test [n.id for n in read_chart(use(code, :delete, :box, "B", nothing)[1]).nodes] == ["A", "C", "D"]
  @test isempty(read_chart(use(code, :delete, :box, "B", nothing)[1]).edges)
end

# A chain of boxes, boxes with an & between them, and two chains on a line
let (; use, reword) = flowchart_edits, code = "flowchart TD\n  A --> B --> C\n  A & B --> D; D --> E\n  subgraph one [The first]\n    F --> G\n  end"
  @test use(code, :delete, :box, "B", nothing)[1] == replace(code, "A --> B --> C" => "C", "A & B --> D" => "A --> D")
  @test use(code, :delete, :line, 2, nothing)[1] == replace(code, "A --> B --> C" => "A --> B\n  C")
  # One of the two lines that an & draws
  less = use(code, :delete, :line, 3, nothing)[1]
  @test [(e.from, e.to) for e in read_chart(less).edges] == [("A", "B"), ("B", "C"), ("B", "D"), ("D", "E"), ("F", "G")]
  @test occursin("D --> E", less)
  @test use(code, :delete, :line, 5, nothing)[1] == replace(code, "A & B --> D; D --> E" => "A & B --> D; E")
  turned = use(code, :turn, :line, 2, nothing)
  @test [(e.from, e.to) for e in read_chart(turned[1]).edges][[1, end]] == [("A", "B"), ("C", "B")] && turned[2] == (:line, 6)
  @test reword(code, :group, 1, "Step one") == replace(code, "one [The first]" => "one[\"Step one\"]")
  @test use(code, :delete, :group, 1, nothing)[1] == "flowchart TD\n  A --> B --> C\n  A & B --> D; D --> E\n    F --> G"
  # The names of new boxes go on from the ones that are taken
  @test use(code, :add, :none, nothing, nothing)[2] == (:box, "H")
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

# --- changing the other kinds ------------------------------------------------------

keys_of(p::Picture) = [(x.kind, x.key) for x in p.parts]

let (; said, reword, tools, use) = pie_edits, code = "pie showData title Pets\n  \"Dogs\" : 30\n  \"Cats\" : 10"
  p = diagram(code)
  # Each slice is a part twice: its piece of the pie, and its name in the list
  @test keys_of(p) == [(:slice, 1), (:slice, 2), (:slice, 1), (:slice, 2), (:title, 1)]
  @test p.parts[1].shape == :area && p.parts[1].words == p.parts[3].words
  @test said(code, :slice, 2) == "Cats: 10" && said(code, :title, 1) == "Pets"
  # A slice's words are its name, then a colon and its number if that changes too
  @test reword(code, :slice, 2, "Birds: 4.5") == replace(code, "\"Cats\" : 10" => "\"Birds\" : 4.5")
  @test reword(code, :slice, 2, "Birds") == replace(code, "\"Cats\" : 10" => "\"Birds\" : 10")
  @test reword(code, :title, 1, "Animals") == replace(code, "title Pets" => "title Animals")
  @test reword("pie\n  title Old\n  \"a\" : 1", :title, 1, "New") == "pie\n  title New\n  \"a\" : 1"
  # A new slice is as big as the others are on average
  @test use(code, :add, :none, nothing, nothing) == (code * "\n  \"New slice\" : 20", (:slice, 3), true)
  @test use(code, :delete, :slice, 1, nothing)[1] == "pie showData title Pets\n  \"Cats\" : 10"
  @test use(code, :delete, :title, 1, nothing)[1] == replace(code, " title Pets" => "")
  @test use(code, :numbers, :none, nothing, nothing)[1] == replace(code, " showData" => "")
  @test use("pie\n  \"a\" : 1", :numbers, :none, nothing, nothing)[1] == "pie showData\n  \"a\" : 1"
  @test use("pie\n  \"a\" : 1", :title, :none, nothing, nothing) == ("pie\n  title Title\n  \"a\" : 1", (:title, 1), true)
  @test [t.name for t in tools(code, :none, nothing)] == [:add, :numbers]
  @test [t.name for t in tools("pie\n  \"a\" : 1", :none, nothing)] == [:add, :title, :numbers]
end

let (; said, reword, tools, use) = state_edits,
    code = "stateDiagram-v2\n  [*] --> Still\n  Still --> Moving : push\n  Moving --> Crash\n  Crash --> [*]\n  state \"Out of fuel\" as Empty\n  Moving --> Empty\n  note right of Still : It waits"
  p = diagram(code)
  # The dot where it starts or ends isn't a part: the arrow beside it is
  @test Set(keys_of(p)) == Set([(:state, "Still"), (:state, "Moving"), (:state, "Crash"), (:state, "Empty"), (:note, 1), ((:move, i) for i in 1:5)...])
  @test length(p.parts) == 10
  @test said(code, :state, "Empty") == "Out of fuel" && said(code, :state, "Still") == "Still" && said(code, :move, 2) == "push" && said(code, :note, 1) == "It waits"
  @test reword(code, :state, "Empty", "No fuel") == replace(code, "\"Out of fuel\"" => "\"No fuel\"")
  # A state that shows its name gets its words on a line after the first that names it
  @test reword(code, :state, "Still", "At rest") == replace(code, "[*] --> Still" => "[*] --> Still\n  Still : At rest")
  @test reword(code, :move, 2, "shove") == replace(code, ": push" => ": shove")
  @test reword(code, :move, 3, "bang") == replace(code, "Moving --> Crash" => "Moving --> Crash : bang")
  @test reword(code, :move, 2, "") == replace(code, " : push" => "")
  @test reword(code, :note, 1, "It rests") == replace(code, "It waits" => "It rests")
  new, picked, typing = use(code, :add, :state, "Crash", nothing)
  @test new == code * "\n  Crash --> S1\n  S1 : New state" && picked == (:state, "S1") && typing
  @test reword(new, :state, "S1", "Fixed") == code * "\n  Crash --> S1\n  S1 : Fixed"
  @test use(code, :join, :state, "Crash", (:state, "Still")) == (code * "\n  Crash --> Still", (:move, 6), false)
  @test use(code, :start, :state, "Moving", nothing)[1] == code * "\n  [*] --> Moving"
  @test use(code, :stop, :state, "Empty", nothing)[1] == code * "\n  Empty --> [*]"
  @test use(code, :note, :state, "Crash", nothing) == (code * "\n  note right of Crash : Note", (:note, 2), true)
  @test use(code, :turn, :move, 2, nothing)[1] == replace(code, "Still --> Moving : push" => "Moving --> Still : push")
  # An arrow goes, and its states stay
  @test use(code, :delete, :move, 4, nothing)[1] == replace(code, "  Crash --> [*]\n" => "")
  @test use(code, :delete, :move, 5, nothing)[1] == replace(code, "  Moving --> Empty\n" => "")
  @test use("stateDiagram-v2\n  A --> B", :delete, :move, 1, nothing)[1] == "stateDiagram-v2\n  A\n  B"
  # A state goes with its arrows and its note
  @test use(code, :delete, :state, "Still", nothing)[1] == "stateDiagram-v2\n  Moving --> Crash\n  Crash --> [*]\n  state \"Out of fuel\" as Empty\n  Moving --> Empty"
  @test use(code, :delete, :note, 1, nothing)[1] == replace(code, "\n  note right of Still : It waits" => "")
  turned = use(code, :way, :none, nothing, "LR")[1]
  @test turned == replace(code, "stateDiagram-v2\n" => "stateDiagram-v2\n  direction LR\n")
  @test use(turned, :way, :none, nothing, "TB")[1] == replace(turned, "direction LR" => "direction TB")
  @test [t.name for t in tools(code, :state, "Still")] == [:add, :join, :start, :stop, :note, :delete]
end

# A state with states in it, and one that's a diamond
let (; said, reword, use) = state_edits, code = "stateDiagram-v2\n  state Moving {\n    Slow --> Fast\n  }\n  state Which <<choice>>\n  Moving --> Done"
  @test (:state, "Moving") in keys_of(diagram(code)) && keys_of(diagram(code))[end] == (:state, "Moving")
  @test reword(code, :state, "Moving", "On the move") == replace(code, "state Moving {" => "state \"On the move\" as Moving {")
  @test said(code, :state, "Which") === nothing
  # The states in it stay, and so does the state that only its arrow named
  @test use(code, :delete, :state, "Moving", nothing)[1] == "stateDiagram-v2\n    Slow --> Fast\n  state Which <<choice>>\n    Done"
end

let (; said, reword, tools, use) = sequence_edits,
    code = "sequenceDiagram\n  participant A as Alice\n  actor B as Bob\n  A->>+B: Hello\n  B-->>-A: Hi\n  Note over A,B: They talk\n  loop Each day\n    A-)C: Ping\n  end"
  p = diagram(code)
  # Someone is a part twice: at the top and at the bottom
  @test count(==((:person, "A")), keys_of(p)) == 2 && count(x -> x[1] == :person, keys_of(p)) == 6
  @test [x for x in keys_of(p) if x[1] != :person] == [(:note, 1), (:message, 1), (:message, 2), (:message, 3)]
  @test said(code, :person, "A") == "Alice" && said(code, :person, "C") == "C" && said(code, :message, 2) == "Hi" && said(code, :note, 1) == "They talk"
  @test reword(code, :person, "A", "Alison") == replace(code, "A as Alice" => "A as Alison")
  @test reword(code, :person, "B", "Robert") == replace(code, "actor B as Bob" => "actor B as Robert")
  # Someone that only a message names gets a line of their own before it, so they keep their place
  @test reword(code, :person, "C", "Carol") == replace(code, "    A-)C: Ping" => "    participant C as Carol\n    A-)C: Ping")
  @test reword(code, :message, 1, "Good day") == replace(code, "A->>+B: Hello" => "A->>+B: Good day")
  @test reword(code, :note, 1, "They chat") == replace(code, "They talk" => "They chat")
  @test use(code, :add, :none, nothing, nothing) == (code * "\n  participant D as Someone", (:person, "D"), true)
  @test use(code, :message, :person, "B", (:person, "A")) == (code * "\n  B->>A: Message", (:message, 4), true)
  @test use(code, :note, :person, "B", nothing) == (code * "\n  Note right of B: Note", (:note, 2), true)
  @test use(code, :drawn, :person, "A", "actor")[1] == replace(code, "participant A as Alice" => "actor A as Alice")
  @test use(code, :drawn, :person, "C", "actor")[1] == replace(code, "    A-)C: Ping" => "    actor C\n    A-)C: Ping")
  @test use(code, :look, :message, 1, "-->>")[1] == replace(code, "A->>+B" => "A-->>+B")
  @test use(code, :turn, :message, 1, nothing)[1] == replace(code, "A->>+B: Hello" => "B->>+A: Hello")
  # A message changes places with the line of code beside it
  @test use(code, :down, :message, 1, nothing) == (replace(code, "A->>+B: Hello\n  B-->>-A: Hi" => "B-->>-A: Hi\n  A->>+B: Hello"), (:message, 2), false)
  new, picked, _ = use(code, :up, :message, 3, nothing)
  @test new == replace(code, "  loop Each day\n    A-)C: Ping" => "  A-)C: Ping\n    loop Each day") && picked == (:message, 3)
  @test use(code, :up, :message, 1, nothing)[2] == (:message, 1)
  @test use(code, :delete, :message, 2, nothing)[1] == replace(code, "  B-->>-A: Hi\n" => "")
  # Someone that only the message named stays
  @test use(code, :delete, :message, 3, nothing)[1] == replace(code, "A-)C: Ping" => "participant C")
  @test use(code, :delete, :person, "B", nothing)[1] == "sequenceDiagram\n  participant A as Alice\n  Note over A: They talk\n  loop Each day\n    A-)C: Ping\n  end"
  @test use(code, :delete, :note, 1, nothing)[1] == replace(code, "  Note over A,B: They talk\n" => "")
  @test [t.name for t in tools(code, :message, 1)] == [:look, :turn, :up, :down, :delete]
end

let (; said, reword, tools, use) = class_edits,
    code = "classDiagram\n  class Animal {\n    +String name\n    +eat(food) void\n  }\n  Animal <|-- Dog : is a\n  Dog \"1\" *-- \"4\" Leg\n  Dog : +bark()\n  note for Dog \"Loud\""
  p = diagram(code)
  @test Set(keys_of(p)) == Set([(:class, "Animal"), (:class, "Dog"), (:class, "Leg"), (:member, ("Animal", 1)), (:member, ("Animal", 2)),
                               (:member, ("Dog", 1)), (:relation, 1), (:relation, 2), (:note, 1)])
  # A line of a class is found before the class that it's in
  @test findfirst(==((:member, ("Animal", 1))), keys_of(p)) < findfirst(==((:class, "Animal")), keys_of(p))
  @test said(code, :class, "Dog") == "Dog" && said(code, :member, ("Animal", 2)) == "+eat(food) void" && said(code, :relation, 1) == "is a" && said(code, :note, 1) == "Loud"
  # A new name of one word is the name of the class in every line that names it
  @test reword(code, :class, "Dog", "Hound") == (replace(code, "Dog" => "Hound"), (:class, "Hound"))
  @test reword(code, :class, "Dog", "Animal") == code   # another class has that name
  # Words with a space in them are shown by a class that keeps its name
  @test reword(code, :class, "Leg", "A leg") == replace(code, "  Dog \"1\" *-- \"4\" Leg" => "  class Leg[\"A leg\"]\n  Dog \"1\" *-- \"4\" Leg")
  @test reword(code, :class, "Animal", "Any animal") == replace(code, "class Animal {" => "class Animal[\"Any animal\"] {")
  @test reword(code, :member, ("Animal", 1), "+int age") == replace(code, "+String name" => "+int age")
  @test reword(code, :member, ("Dog", 1), "+wag()") == replace(code, "Dog : +bark()" => "Dog : +wag()")
  @test reword(code, :relation, 1, "kind of") == replace(code, ": is a" => ": kind of")
  @test reword(code, :relation, 2, "has") == replace(code, "Dog \"1\" *-- \"4\" Leg" => "Dog \"1\" *-- \"4\" Leg : has")
  @test reword(code, :note, 1, "Barks") == replace(code, "\"Loud\"" => "\"Barks\"")
  @test use(code, :add, :none, nothing, nothing) == (code * "\n  class Class1", (:class, "Class1"), true)
  @test use(code, :add, :class, "Dog", nothing)[1] == code * "\n  Dog <|-- Class1"
  # A new line of a class goes in its { }, or after the last line that says something of the class
  new, picked, typing = use(code, :line, :class, "Animal", nothing)
  @test new == replace(code, "    +eat(food) void\n" => "    +eat(food) void\n    +name\n") && picked == (:member, ("Animal", 2)) && typing
  new, picked, _ = use(code, :line, :class, "Dog", nothing)
  @test new == replace(code, "  Dog : +bark()" => "  Dog : +bark()\n  Dog : +name") && picked == (:member, ("Dog", 1))
  new, picked, _ = use(code, :line, :class, "Leg", nothing)
  @test new == replace(code, "  Dog \"1\" *-- \"4\" Leg" => "  Dog \"1\" *-- \"4\" Leg\n  Leg : +name") && picked == (:member, ("Leg", 1))
  @test use(code, :join, :class, "Leg", (:class, "Animal")) == (code * "\n  Leg --> Animal", (:relation, 3), false)
  @test use(code, :look, :relation, 1, ("", ">", true))[1] == replace(code, "Animal <|-- Dog" => "Animal ..> Dog")
  @test use(code, :turn, :relation, 1, nothing)[1] == replace(code, "Animal <|-- Dog" => "Dog --|> Animal")
  @test use(code, :turn, :relation, 2, nothing)[1] == replace(code, "Dog \"1\" *-- \"4\" Leg" => "Leg \"4\" --* \"1\" Dog")
  @test use(code, :note, :class, "Leg", nothing) == (code * "\n  note for Leg \"Note\"", (:note, 2), true)
  @test use(code, :delete, :member, ("Animal", 2), nothing)[1] == replace(code, "    +eat(food) void\n" => "")
  # A class that only the line named stays
  @test use(code, :delete, :relation, 2, nothing)[1] == replace(code, "Dog \"1\" *-- \"4\" Leg" => "class Leg")
  @test use(code, :delete, :note, 1, nothing)[1] == replace(code, "\n  note for Dog \"Loud\"" => "")
  @test use(code, :delete, :class, "Animal", nothing)[1] == "classDiagram\n  Dog \"1\" *-- \"4\" Leg\n  Dog : +bark()\n  note for Dog \"Loud\""
  @test use(code, :way, :none, nothing, "LR")[1] == replace(code, "classDiagram\n" => "classDiagram\n  direction LR\n")
end

# Every change that a tool makes to a diagram of each kind leaves code that can still be drawn
for code in ("flowchart TD\n  A[One] --> B{Two}\n  B -->|x| C((Three))", "sequenceDiagram\n  A->>B: Hi\n  Note over A: n\n  B-->>A: Yo",
             "stateDiagram-v2\n  [*] --> A\n  A --> B : go\n  note left of A : n", "classDiagram\n  A <|-- B\n  A : +x\n  note for A \"n\"",
             "pie title T\n  \"a\" : 1\n  \"b\" : 2")
  edits = getfield(parentmodule(Mermaid), :EDITORS)[kind(code)]
  for part in [nothing; unique(keys_of(diagram(code)))], tool in edits.tools(code, something(part, (:none, nothing))...)
    args = !isempty(tool.choices) ? last.(tool.choices) : tool.target ? [k for k in unique(keys_of(diagram(code)))] : [nothing]
    for arg in args
      new = edits.use(code, tool.name, something(part, (:none, nothing))..., arg)
      @test diagram(new[1]) isa Picture
      @test new[2] === nothing || new[2] in keys_of(diagram(new[1]))
    end
  end
  for part in unique(keys_of(diagram(code)))
    edits.said(code, part...) === nothing && continue
    new = edits.reword(code, part..., "Other words")
    new isa Tuple && (new = new[1])
    @test diagram(new) isa Picture
  end
end

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

# --- changing it where it's drawn --------------------------------------------------

# A diagram that can't be changed takes no click, and has no tools
let m = Mermaid("flowchart LR\n  A[One] --> B[Two]")
  w = Window(Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, m), size=(400px, 200px))
  frame(w)
  @test isempty(tools(m)) && !pick_at!(m, 20, 20) && m.picked === nothing
end

# A layout is made once. A semantic node around the diagram has it described again when it changes.
@def mutable struct Page <: SemanticUI end
describe(p::Page) = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, padding(12px), background(light.surface), p.firstchild)

let code = "flowchart LR\n  A[One] --> B{Two}\n  B -- yes --> C[Three]", seen = String[]
  m = Mermaid(code, editing=true, onchange=m -> push!(seen, m.code))
  w = Window(Page(m), size=(700px, 300px))
  frame(w)
  key(k) = (onkey(w, KeyPress{k}(0, w)); frame(w))
  type(s) = (foreach(c -> ontype(w, Typed(c, w)), s); frame(w))
  # The place in the window of the middle of a part of the picture
  at(which) = (p = part(m, which); x = p.words; (px(m.place[1] + x[1] * m.place[3]), px(m.place[2] + x[2] * m.place[3])))
  # Its tools show as buttons over the picture, which is under them
  @test [t.name for t in tools(m)] == [:add, :way]
  @test m.place[2] > 12 + 28
  buttons() = [b for b in values(getfield(m, :kept)) if b isa ToolButton && rect(b) !== nothing]
  @test length(buttons()) == 2

  # A click selects a box, and the tools are the box's
  click!(w, at((:box, "B")))
  frame(w)
  @test m.picked == (:box, "B") && [t.name for t in tools(m)] == [:add, :join, :shape, :delete]
  @test length(buttons()) == 4
  @test part_at(m, part(m, (:line, 1)).words...).kind == :line
  picture = joinpath(get(ENV, "MERMAID_PICTURES", mktempdir()), "picked.png")
  save_png(picture, w)
  @test length(unique(pixels(picture))) > 2

  # A second click types its words, where they are. Return takes them.
  click!(w, at((:box, "B")))
  frame(w)
  @test m.typing == (:box, "B") && w.focus === m.field && m.field.text == "Two"
  type(" more")
  # The diamond is too small for the words, so it grows as they're typed, and its glow with it
  M = parentmodule(Mermaid)
  diamond = part(m, (:box, "B"))
  big = Base.invokelatest(getfield(M, :grown), m, diamond)
  @test big !== nothing && pictured(m).items[first(big)] isa Shape && last(big).kind == :diamond
  @test last(big).w > diamond.box[3] && last(big).h == diamond.box[4]
  save_png(joinpath(dirname(picture), "typing.png"), w)
  key(Keys.enter)
  @test m.typing === nothing && m.code == replace(code, "B{Two}" => "B{Two more}") && seen == [m.code]
  @test w.focus === m && m.picked == (:box, "B")
  # Esc leaves the words as they were
  key(Keys.enter)
  @test m.typing == (:box, "B")
  type("x")
  key(Keys.escape)
  @test m.typing === nothing && length(seen) == 1
  # A line's label has no box to grow. What's behind the words covers the line under them.
  m.picked = (:line, 2)
  @test retype!(m)
  type(" and some more")
  @test Base.invokelatest(getfield(M, :grown), m, part(m, (:line, 2))) === nothing
  save_png(joinpath(dirname(picture), "label.png"), w)
  key(Keys.escape)
  m.picked = (:box, "B")
  @test m.typing === nothing && length(seen) == 1

  # A tool that needs another box waits for a click on one
  @test use!(m, :join) && m.waiting == :join
  click!(w, at((:box, "A")))
  frame(w)
  @test m.waiting === nothing && endswith(m.code, "\n  B --> A") && m.picked == (:line, 3)
  frame(w)
  save_png(joinpath(dirname(picture), "line.png"), w)
  # A tool with choices takes one of them
  @test !use!(m, :look) && use!(m, :look, (:dotted, :none, :arrow)) && endswith(m.code, "\n  B -.-> A")
  # ⌫ takes the selected part away, and then nothing is selected
  key(Keys.backspace)
  @test !occursin("B -.-> A", m.code) && m.picked === nothing

  # A new box is selected with its words ready to type over
  @test use!(m, :add)
  frame(w)
  @test m.picked == (:box, "D") && m.typing == (:box, "D") && m.field.anchor == 0 && m.field.cursor == length("New box")
  # They're typed in the box itself, with no box of their own, in place of the words that the box shows
  new = part(m, (:box, "D"))
  pen_wide(s) = wide(Pen(m.made[1][2], m.made[1][3]), s; size=typed.size, bold=typed.bold, italic=typed.italic)
  own = Base.invokelatest(getfield(M, :own_words), m, new)
  @test [pictured(m).items[i].text for i in own] == ["New box"]
  typed = Base.invokelatest(getfield(M, :typed_words), m, new)
  @test typed.text == "New box" && typed.x ≈ pictured(m).items[own[1]].x - pen_wide("New box") / 2
  save_png(joinpath(dirname(picture), "new_box.png"), w)
  type("Four")
  frame(w)
  typed = Base.invokelatest(getfield(M, :typed_words), m, new)
  @test typed.text == "Four" && typed.x ≈ new.words[1] - pen_wide("Four") / 2
  save_png(joinpath(dirname(picture), "new_box_typed.png"), w)
  click!(w, at((:box, "A")))   # a click somewhere else takes the words too
  frame(w)
  @test occursin("D[Four]", m.code) && m.picked == (:box, "A") && m.typing === nothing
  # A click on nothing selects nothing
  click!(w, (px(m.place[1] + 1), px(m.place[2] + 1)))
  @test m.picked === nothing
  # A change that would make code that can't be drawn isn't made
  @test !Base.invokelatest(getfield(parentmodule(Mermaid), :change!), m, "flowchart LR\n  A[") && occursin("D[Four]", m.code)
end

# While the mouse is over a box, a point shows on the box's edge. Drag the point onto another box, and a line goes to it.
let code = "flowchart LR\n  A[One] --> B[Two]\n  C[Three]", seen = String[]
  m = Mermaid(code, editing=true, onchange=m -> push!(seen, m.code))
  w = Window(Page(m), size=(700px, 300px))
  frame(w)
  pictures = get(ENV, "MERMAID_PICTURES", mktempdir())
  # The place in the window of a place in the picture
  win(p) = (px(m.place[1] + p[1] * m.place[3]), px(m.place[2] + p[2] * m.place[3]))
  down() = (w.keys |= Keys.mouse_left; onkey(w, KeyPress{Keys.mouse_left}(0, w)); frame(w))
  up() = (w.keys ⊻= Keys.mouse_left; onkey(w, KeyRelease{Keys.mouse_left}(0, w)); frame(w))
  b = part(m, (:box, "B"))
  move!(w, win(b.words))
  @test m.hovered == b && !m.on_point
  # The lines of this diagram go right, so the point is in the middle of the box's right side
  point = point_of(m, b)
  @test point == (b.box[1] + b.box[3], b.box[2] + b.box[4] / 2)
  move!(w, win(point))
  @test m.hovered == b && m.on_point
  save_png(joinpath(pictures, "point.png"), w)
  # Away from the boxes, no point shows
  move!(w, win((1.0, 1.0)))
  @test m.hovered === nothing

  # A drag from the point onto box C draws a line from B to C, and selects the line
  move!(w, win(point))
  down()
  @test m.joining !== nothing
  c = part(m, (:box, "C"))
  move!(w, win(c.words))
  @test landing(m) == c
  save_png(joinpath(pictures, "joining.png"), w)
  up()
  @test m.joining === nothing && endswith(m.code, "\n  B --> C") && seen == [m.code] && m.picked[1] == :line

  # Let go away from the boxes, and no line is drawn. The box it's from is selected.
  b = part(m, (:box, "B"))
  move!(w, win(point_of(m, b)))
  down()
  move!(w, win((1.0, 1.0)))
  up()
  @test m.joining === nothing && length(seen) == 1 && m.picked == (:box, "B")
  # A press on a box that isn't on its point selects the box, as a click does
  a = part(m, (:box, "A"))
  click!(w, win(a.words))
  @test m.picked == (:box, "A") && m.joining === nothing
end
