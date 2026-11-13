@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "./abstract" SemanticUI describe inputs skipping add_child! detach! dark light with_theme
@use "./Geometric"... parse_color
@use "./Specific"...
@use "./draw" frame rect scene ishovered redraw_in!
@use "./testing"...
@use GeometryBasics: Vec2
@use Random: Xoshiro

# How many times each node's `describe` has run
const runs = IdDict{Any,Int}()
ran!(node) = runs[node] = get(runs, node, 0) + 1
ran(node) = get(runs, node, 0)

# A line of text with lines of its own under it. It says what its `describe` reads, so it can be skipped.
@def mutable struct Line <: SemanticUI
  text::String = ""
  tall::Bool = false
  across::Bool = false   # the lines under it are side by side, so each one's width depends on how many there are
  grows::Bool = false    # it takes a share of the spare height, so its height depends on the lines beside it
end
inputs(l::Line) = (l.text, l.tall, l.across, l.grows)
describe(l::Line) = begin
  ran!(l)
  under = l.across ? Row(width(grow=GrowType.Grow), child_gap=4px, Alignment.Start, l.children...) :
                     Column(width(grow=GrowType.Grow), Alignment.Start, l.children...)
  Column(width(grow=GrowType.Grow), l.grows ? height(grow=GrowType.Grow) : height(), padding(0px, 0px, 0px, 10px), Alignment.Start,
    Row(width(grow=GrowType.Grow), height(min=l.tall ? 40px : 0px), padding(4px), background(ishovered(l) ? "yellow" : "white"), Text(l.text)),
    under)
end

@def mutable struct Board <: SemanticUI
  title::String = "Board"
end
inputs(b::Board) = (b.title,)
describe(b::Board) = (ran!(b); Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, Text(b.title), b.children...))

# A node with no `inputs` is described on every frame. This one sets the theme of what's in it.
@def mutable struct Shell <: SemanticUI
  dark::Bool = false
end
describe(s::Shell) = with_theme(s.dark ? dark : light) do
  ran!(s)
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, s.firstchild)
end

let a = Line(text="one"), b = Line(Line(text="two and a half"); text="two"), c = Line(text="three"),
    board = Board(a, b, c), shell = Shell(board), w = Window(shell, size=(200px, 300px))
  lines = (a, b, b.firstchild, c)
  counts() = collect(map(ran, (board, lines...)))
  start = Int[]
  # Defined before the first frame: defining a function counts as loading code, which describes everything again
  since() = counts() .- start
  # The mouse starts in the corner, over the board. The second frame knows that, and describes the board again.
  move!(w, (199, 299)); frame(w)
  append!(start, counts())
  rects = map(rect, lines)

  # Nothing has changed, so nothing is described again and each node has the rectangle it had
  shell_ran = ran(shell)
  frame(w); frame(w)
  @test since() == [0, 0, 0, 0, 0]
  @test ran(shell) == shell_ran + 2
  @test all(map(rect, lines) .=== rects)

  # A change to one node describes that node only. Its new geometry goes where its old was,
  # and the layout moves the nodes below it.
  below = rect(c).top
  b.firstchild.tall = true
  frame(w)
  @test since() == [0, 0, 0, 1, 0]
  @test rect(a) === rects[1]
  @test rect(c).top > below
  @test rect(b.firstchild).children[1].height == 40px
  @test sprint(show, rect(a)) == "ConcreteRect of Column, 200px × $(rect(a).height) at (0px, $(rect(a).top))"   # short enough to read

  # The mouse going onto a node describes it again, because the library adds that to its inputs
  move!(w, a)
  @test since() == [0, 1, 0, 1, 0]
  @test rect(a).children[1].from.background.color == parse_color("yellow")
  move!(w, (199, 299))
  @test since() == [0, 2, 0, 1, 0]

  # A new child describes its parent again, and not the children it had
  d = Line(text="four")
  add_child!(board, d)
  frame(w)
  @test since() == [1, 2, 0, 1, 0] && ran(d) == 1
  @test rect(d).top > rect(c).top
  detach!(c)
  frame(w)
  @test since()[1] == 2 && rect(c) === nothing

  # Another theme, or another size of window, describes everything again
  before = since()
  shell.dark = true
  frame(w)
  @test since()[1:4] == before[1:4] .+ 1
  w.size = Vec2{px}(260px, 300px)
  frame(w)
  @test since()[1:4] == before[1:4] .+ 2
  @test rect(a).width == 260px

  # With skipping off, everything is described on every frame
  skipping[] = false
  frame(w); frame(w)
  @test since()[1:4] == before[1:4] .+ 4
  skipping[] = true
end

# A layout as a list of numbers and lines of text, to compare two layouts
flat(ui, out=Any[]) = begin
  push!(out, ui.left.value, ui.top.value, ui.width.value, ui.height.value)
  ui isa ConcreteText ? append!(out, ui.lines) : foreach(child -> flat(child, out), ui.children)
  out
end

# A node that isn't described again can still be given another size, when what's beside it changes.
# Then the layout does what's in it again. Each case gives how often `a` was described after the
# change, and its size before and after. Without skipping it's described again, and the sizes agree.
squeezed(skip) = begin
  skipping[] = skip
  a, b = Line(text="one two three four five six seven"), Line(text="b")
  top = Line(a, b; text="top", across=true)
  w = Window(Shell(Board(top)), size=(200px, 300px))
  move!(w, (199, 299)); frame(w)
  start, before = ran(a), rect(a).size
  add_child!(top, Line(text="c"))                 # three side by side where there were two
  frame(w)
  skipping[] = true
  (ran(a) - start, before, rect(a).size, flat(scene(w)))
end
let (again, before, after, layout) = squeezed(true), (_, was, now, expected) = squeezed(false)
  @test again == 0
  @test after[1] < before[1] && after[2] > before[2]     # narrower, so its text wraps into more lines
  @test (before, after) == (was, now)
  @test layout == expected
end

stretched(skip) = begin
  skipping[] = skip
  a, b = Line(text="a", grows=true), Line(text="b", grows=true)
  board = Board(a, b)
  w = Window(Shell(board), size=(200px, 300px))
  move!(w, (199, 299)); frame(w)
  start, before = ran(a), rect(a).size
  add_child!(board, Line(text="c", grows=true))   # three share the spare height where two did
  frame(w)
  skipping[] = true
  (ran(a) - start, before, rect(a).size, flat(scene(w)))
end
let (again, before, after, layout) = stretched(true), (_, was, now, expected) = stretched(false)
  @test again == 0
  @test after[2] < before[2]
  @test (before, after) == (was, now)
  @test layout == expected
end

# Code that's loaded again while the app runs describes everything again, so a change to a `describe` shows
let a = Line(text="a"), w = Window(Shell(Board(a)), size=(200px, 300px))
  move!(w, (199, 299)); frame(w)
  start = ran(a)
  frame(w)
  @test ran(a) == start
  @eval loaded_again() = nothing
  frame(w)
  @test ran(a) == start + 1
  frame(w)
  @test ran(a) == start + 1
end

# A `describe` that asks for another frame is run again on that frame, whatever its inputs are
@def mutable struct Clock <: SemanticUI end
inputs(::Clock) = ()
describe(c::Clock) = (ran!(c); redraw_in!(c, 1); Box(width(20px), height(20px)))
let clock = Clock(), w = Window(Board(clock), size=(100px, 100px))
  frame(w); frame(w); frame(w)
  @test ran(clock) == 3
end

# A window that skips what hasn't changed lays out exactly what one that describes everything does.
# Make the same changes to two copies of an app, one with skipping and one without, and compare.
const words = split("the quick brown fox jumps over a lazy dog and then runs on through the long wet grass")
phrase(rng) = join(rand(rng, words, rand(rng, 1:9)), " ")
every(node, out=Line[]) = (node isa Line && push!(out, node); foreach(child -> every(child, out), node.children); out)

"Make one change, picked by `rng`, to the app in `w`"
change!(rng, w, board) = begin
  lines = every(board)
  kind = rand(rng, 1:10)
  if kind == 1 && !isempty(lines)
    rand(rng, lines).text = phrase(rng)
  elseif kind == 2 && !isempty(lines)
    line = rand(rng, lines); line.tall = !line.tall
  elseif kind == 3
    add_child!(isempty(lines) || rand(rng, Bool) ? board : rand(rng, lines), Line(text=phrase(rng)))
  elseif kind == 4 && length(lines) > 1
    detach!(rand(rng, lines))
  elseif kind == 5
    w.size = Vec2{px}(px(rand(rng, 120:10:320)), px(rand(rng, 200:20:400)))
  elseif kind == 6
    pos = Vec2{px}(px(rand(rng, 0:300)), px(rand(rng, 0:400)))
    onmouse(w, MouseMove(pos, w)); w.mouse = pos
  elseif kind == 7
    board.title = phrase(rng)
  elseif kind == 8 && !isempty(lines)
    line = rand(rng, lines); line.across = !line.across
  elseif kind == 9 && !isempty(lines)
    line = rand(rng, lines); line.grows = !line.grows
  end                        # and 10 changes nothing
  frame(w)
  flat(scene(w))
end
@use "github.com/jkroso/MiniFB.jl" MouseMove onmouse

history(skip, seed) = begin
  skipping[] = skip
  rng = Xoshiro(seed)
  board = Board(Line(text="one"), Line(Line(text="inside"); text="two"))
  w = Window(Shell(board), size=(200px, 300px))
  frame(w)
  try
    [change!(rng, w, board) for _ in 1:400]
  finally
    skipping[] = true
  end
end

for seed in 1:4
  with, without = history(true, seed), history(false, seed)
  different = findfirst(i -> with[i] != without[i], eachindex(with))
  different === nothing || @info "with seed $seed the layouts first differ after change $different"
  @test different === nothing
end
