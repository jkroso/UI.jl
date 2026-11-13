@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "./abstract" SemanticUI describe
@use "./Geometric"...
@use "./Specific"...
@use "./draw" inside hittest

# The middle of this 400×300 box is (200, 150) and the biggest circle in it has a
# radius of 150, so a wedge's radii of 0.2 and 0.6 are 30px and 90px
const quarter = Wedge(width(400px), height(300px), inner=0.2, outer=0.6, start=0, sweep=90)
let wedge = describe(quarter, (400px, 300px))
  @test inside(wedge, (250px, 100px))      # up and to the right: in the slice
  @test !inside(wedge, (150px, 100px))     # up and to the left: outside its angles
  @test !inside(wedge, (210px, 140px))     # too near the middle
  @test !inside(wedge, (300px, 20px))      # too far out, though still in its box
end

# Its angles can wrap past 12 o'clock
const top = Wedge(width(400px), height(300px), outer=1.0, start=315, sweep=90)
let wedge = describe(top, (400px, 300px))
  @test inside(wedge, (180px, 50px)) && inside(wedge, (220px, 50px))
  @test !inside(wedge, (200px, 250px))
end

# Wedges stacked in one box each get the clicks on their own slice
@def mutable struct Slice <: SemanticUI
  start::Float64 = 0.0
end
describe(s::Slice) = Wedge(width(grow=GrowType.Grow), height(grow=GrowType.Grow), start=s.start, sweep=180)
const left, right = Slice(start=180), Slice(start=0)
const pie = Stack(width(200px), height(200px), right, left)
let scene = describe(pie, (200px, 200px))
  @test hittest(scene, (150px, 100px)) === right
  @test hittest(scene, (50px, 100px)) === left
end

# A shadow is drawn outside its box only. This box is see-through, at 30–70px each way,
# and its shadow is 10px lower, so only the 10px below the box are black
@use "./draw" draw
@use "github.com/jkroso/MiniFB.jl/skia" drawing
const lifted = Box(width(100px), height(100px), padding(30px), Box(width(40px), height(40px), shadow(0, 10, 0, "black")))
let pixels = drawing(draw, (100px, 100px), describe(lifted, (100px, 100px)), scale=(1f0, 1f0))
  drawn(x, y) = reinterpret(UInt32, pixels[y, x]) != 0
  @test drawn(50, 75)        # below the box
  @test !drawn(50, 50)       # inside the box
  @test !drawn(50, 85)       # past the end of the shadow
  @test !drawn(25, 75)       # left of it
end

# A blur takes the shadow further out, and `spread` further still
let soft = Box(width(100px), height(100px), padding(30px), Box(width(40px), height(40px), shadow(0, 0, 8, "black", spread=4px)))
  pixels = drawing(draw, (100px, 100px), describe(soft, (100px, 100px)), scale=(1f0, 1f0))
  shade(x, y) = reinterpret(UInt32, pixels[y, x]) >> 24
  @test shade(50, 72) > shade(50, 76) > 0
  @test shade(50, 50) == 0
end

# A node that `describe` makes afresh on each frame, like the arrow of a dropdown, is the same node
# from one frame to the next. Without that, the cursor resting on it asks for a new frame for ever.
@use "./abstract" GeometricUI handled
@use "./draw" update_hover! ishovered emit
@use "./Semantic/Dropdown" Dropdown
@use "./Semantic/Icon" Icon
@use "./Semantic/Button" Button
@use "github.com/jkroso/MiniFB.jl" Window KeyPress Keys MouseMove onkey onmouse
@def mutable struct Page <: SemanticUI end
describe(p::Page) = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), Alignment.Start, p.children...)
let w = Window(Page(Dropdown(options=["a", "b"]), Dropdown(options=["c", "d"])), size=(300px, 100px))
  scene() = describe(convert(GeometricUI, w.ui), (300px, 100px))
  arrow, other, label = (282px, 18px), (282px, 54px), (50px, 18px)
  @test hittest(scene(), arrow) isa Icon
  @test update_hover!(w, scene(), arrow)          # the cursor arrives
  @test !update_hover!(w, scene(), arrow)         # and stays
  @test !update_hover!(w, scene(), arrow)
  @test ishovered(hittest(scene(), arrow))        # this frame's arrow is the one the cursor is over
  @test !ishovered(hittest(scene(), other))       # the other dropdown's arrow isn't
  @test update_hover!(w, scene(), other)          # moving to that one is a change
  @test update_hover!(w, scene(), label)
  @test !update_hover!(w, scene(), label)
end

# An event goes up through the semantic nodes until a handler returns `handled`
@def mutable struct Clickable <: SemanticUI
  clicks::Int = 0
  stops::Bool = false
end
describe(c::Clickable) = Row(width(grow=GrowType.Grow), c.children...)
onkey(c::Clickable, ::KeyPress{Keys.mouse_left}) = (c.clicks += 1; c.stops ? handled : nothing)
let w = Window(Box(), size=(100px, 100px)), click = KeyPress{Keys.mouse_left}(0, w)
  outer = Clickable(Clickable(Clickable()))
  middle = outer.firstchild
  @test emit(middle.firstchild, click) === nothing
  @test (middle.firstchild.clicks, middle.clicks, outer.clicks) == (1, 1, 1)
  middle.stops = true
  @test emit(middle.firstchild, click) === handled
  @test (middle.firstchild.clicks, middle.clicks, outer.clicks) == (2, 2, 1)
  # A button with an `onclick` keeps its click. One without lets it go on up.
  pressed = Ref(0)
  row = Clickable(Button("Delete", onclick=_ -> pressed[] += 1), Button("Label"))
  emit(row.children[1], click)
  @test (pressed[], row.clicks) == (1, 0)
  emit(row.children[2], click)
  @test row.clicks == 1
end

# `rect` tells a node where the last layout put it. A component that's put straight into a layout finds its window too.
@use "./draw" rect frame scene
@use "./Semantic/Checkbox" Checkbox
let box = Checkbox(), w = Window(Column(width(200px), height(100px), padding(10px), Alignment.Start, Box(height(30px)), box), size=(200px, 100px))
  @test rect(box) === nothing        # nothing is laid out yet
  frame(w)
  @test rect(box).top == 40px && rect(box).left == 10px
  @test scene(w).width == 200px
end

# A Scroll that `describe` makes anew on each frame stays where it was scrolled to
@use "github.com/jkroso/MiniFB.jl" onscroll
@use GeometryBasics: Vec2
@def mutable struct Feed <: SemanticUI end
tall() = Column(width(grow=GrowType.Grow), (Box(height(50px)) for _ in 1:20)...)
describe(f::Feed) = Row(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                        Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow), tall()),
                        Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow), tall()))
let w = Window(Feed(), size=(200px, 100px))
  scrolls() = Tuple(c.from for c in scene(w).children)
  frame(w)
  first_frame = scrolls()
  w.mouse = Vec2{px}(150px, 50px)             # over the Scroll on the right
  onscroll(w, Vec2{px}(0px, -2px))
  frame(w)
  @test scrolls()[2] !== first_frame[2]        # each frame has Scrolls of its own
  @test scrolls()[2].offset == 60px
  @test scrolls()[1].offset == 0px             # and the two don't share a place
  @test scrolls()[2].content_height == 1000px
end

# The wheel moves the Scroll under the mouse. When that Scroll is at its end, a
# new run of the wheel moves the Scroll round it.
@def mutable struct Nest <: SemanticUI end
describe(n::Nest) = Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                           Column(width(grow=GrowType.Grow),
                                  Scroll(width(grow=GrowType.Grow), height(80px), key=:inner, tall()),
                                  tall()))
let w = Window(Nest(), size=(200px, 100px))
  frame(w)
  outer() = scene(w).from
  inner() = scene(w).children[1].children[1].from
  w.mouse = Vec2{px}(100px, 40px)              # over the Scroll that's inside
  onscroll(w, Vec2{px}(0px, -1px))
  frame(w)
  @test inner().offset == 30px && outer().offset == 0px
  # The same run of the wheel stays with the inner Scroll when it gets to its end
  foreach(_ -> onscroll(w, Vec2{px}(0px, -100px)), 1:3)
  frame(w)
  @test inner().offset == 920px && outer().offset == 0px
  # ... and a new run moves the outer one
  sleep(0.25)
  onscroll(w, Vec2{px}(0px, -1px))
  frame(w)
  @test inner().offset == 920px && outer().offset == 30px
  # The other way, the inner Scroll has somewhere to go, so it moves
  sleep(0.25)
  w.mouse = Vec2{px}(100px, 40px)
  onscroll(w, Vec2{px}(0px, 1px))
  frame(w)
  @test inner().offset == 890px && outer().offset == 30px
end

# Each corner of a box has its own radius. Here the two at the top are round and the two at the bottom are square.
paint(ui, size=(40px, 40px)) = drawing(draw, size, describe(ui, size), scale=(1f0, 1f0))
inked(pixels, x, y) = reinterpret(UInt32, pixels[y, x]) >> 24 > 0x80
let pixels = paint(Box(width(40px), height(40px), radius(20px, 0px), background("black")))
  @test !inked(pixels, 2, 2) && !inked(pixels, 39, 2)       # the top corners are cut off
  @test inked(pixels, 2, 39) && inked(pixels, 39, 39)       # the bottom ones aren't
  @test inked(pixels, 20, 2)
end

# A dashed border has gaps along it, and a solid one has none
runs(pixels, y, xs) = count(i -> inked(pixels, xs[i], y) != inked(pixels, xs[i+1], y), 1:length(xs)-1)
let dashed = paint(Box(width(40px), height(40px), border(2px, :dashed, "black"))),
    dotted = paint(Box(width(40px), height(40px), border(2px, :dotted, "black"))),
    solid = paint(Box(width(40px), height(40px), border(2px, :solid, "black")))
  @test runs(solid, 1, 5:35) == 0
  @test runs(dashed, 1, 5:35) >= 4
  @test runs(dotted, 1, 5:35) > runs(dashed, 1, 5:35)
end

# A double border is two lines with a gap between them
let pixels = paint(Box(width(40px), height(40px), border(9px, :double, "black")))
  @test inked(pixels, 20, 2) && !inked(pixels, 20, 5) && inked(pixels, 20, 8) && !inked(pixels, 20, 12)
end

# A Text's `weight` picks how heavy its letters are, and a `subfamily` wins over it
@use "./Specific" text_width style
let plain = Text("mmmmmmmm", family="Helvetica"), bold = Text("mmmmmmmm", family="Helvetica", weight=700)
  @test style(plain) == "" && style(bold) == "Bold"
  @test text_width(bold, bold.content) > text_width(plain, plain.content)
  @test style(Text("m", weight=700, subfamily="Light")) == "Light"
end

# A menu is an ordinary node in a popup. A click on an item picks it, and a click outside closes it.
@use "./draw" show_menu! popup! popups hide_menu! show_tooltip!
@use "./Semantic/Menu" Menu Item onselect
let picked = Int[], w = Window(Page(Dropdown(options=["a", "b"])), size=(300px, 200px))
  mouse(x, y) = (pos = Vec2{px}(px(x), px(y)); onmouse(w, MouseMove(pos, w)); w.mouse = pos; frame(w))
  click(x, y) = (mouse(x, y); onkey(w, KeyPress{Keys.mouse_left}(0, w)); frame(w))
  press(k) = (onkey(w, KeyPress{k}(0, w)); frame(w))
  open() = (show_menu!(w, ["Cut", "Copy", "Paste"], 100px, 50px, 120px, onselect=i -> push!(picked, i)); frame(w))
  frame(w)
  open()
  menu = only(popups(w)).scene
  @test (menu.left, menu.top, menu.width) == (100px, 50px, 120px)
  click(110, 50 + 1 + 32 + 16)                       # the middle of the second item
  @test picked == [2] && isempty(popups(w))
  open(); click(20, 150)                             # outside the menu
  @test picked == [2, 0] && isempty(popups(w))
  # The arrow keys move the highlight, Return picks, and Escape closes
  open(); press(Keys.down); press(Keys.down); press(Keys.down); press(Keys.up); press(Keys.enter)
  @test picked == [2, 0, 2]
  open(); press(Keys.up); press(Keys.enter)          # up from nothing goes to the last item
  @test picked == [2, 0, 2, 3]
  open(); press(Keys.escape)
  @test picked == [2, 0, 2, 3, 0] && isempty(popups(w))

  # A dropdown opens its menu under itself, and the menu's click doesn't reach the app behind it
  dropdown = w.ui.firstchild
  click(50, 18)
  @test dropdown.open
  menu = only(popups(w)).scene
  @test menu.top == rect(dropdown).top + rect(dropdown).height + 2px
  press(Keys.down); press(Keys.down); press(Keys.enter)
  @test dropdown.selected == 2 && !dropdown.open

  # The menu stays under the dropdown when the dropdown moves, and closes when the dropdown is gone
  click(50, 18)
  spacer = Box(height(30px))
  w.ui.firstchild = spacer; spacer.nextsibling = dropdown; dropdown.prevsibling = spacer; setfield!(spacer, :parent, w.ui)
  frame(w)
  @test rect(dropdown).top == 30px
  @test only(popups(w)).scene.top == rect(dropdown).top + rect(dropdown).height + 2px
  w.ui.firstchild = spacer; spacer.nextsibling = nothing
  frame(w)
  @test isempty(popups(w)) && !dropdown.open
  w.ui.firstchild = dropdown; dropdown.prevsibling = nothing; frame(w)

  # A menu near the bottom of the window moves up to stay in it
  show_menu!(w, ["One", "Two", "Three"], 100px, 190px, 120px); frame(w)
  bottom = only(popups(w)).scene
  @test bottom.top + bottom.height <= 200px
  hide_menu!(w)

  # A tooltip is beside its target, the mouse goes through it, and the next mouse move takes it away
  show_tooltip!(w, Box(padding(8px, 5px), Text("Save")), 100px, 100px, 40px, 20px, placement=:bottom); frame(w)
  tip = only(popups(w)).scene
  @test tip.top == 124px && tip.left + tip.width / 2 == 120px
  @test hittest(w, Vec2{px}(120px, 130px)) isa Page        # the page behind it, not the tooltip
  mouse(10, 150)
  @test isempty(popups(w))
end

# A `Menu` of `Item`s tells `onselect` which item was clicked
const chosen = Int[]
onselect(::Menu, i::Int) = push!(chosen, i)
let w = Window(Page(), size=(300px, 200px)), menu = Menu(Item("Cut"), Item("Copy"))
  frame(w)
  show_menu!(w, menu, 20px, 20px, 160px); frame(w)
  pos = Vec2{px}(60px, 20px + 4px + 1px + 32px + 10px)       # in the second item
  onmouse(w, MouseMove(pos, w)); w.mouse = pos; frame(w)
  onkey(w, KeyPress{Keys.mouse_left}(0, w))
  @test chosen == [2] && isempty(popups(w))
end

# Helvetica has no medium weight. Like CSS, 500 then gives its regular letters, not its bold ones.
let wide(weight) = text_width(Text("mmmmmmmm", family="Helvetica", weight=weight), "mmmmmmmm")
  @test wide(500) == wide(400) < wide(700)
end

# A window uses a layout again while nothing in it has changed, and notices a change by itself
@use "./draw" resolve_layout
let tree = Column(width(100px), height(100px), Alignment.Start, Box(height(20px)), Box(height(30px)))
  id = UInt(1)
  first_layout = resolve_layout(tree, Vec2{px}(100px, 100px), id)
  @test resolve_layout(tree, Vec2{px}(100px, 100px), id) === first_layout
  tree.children[1].height = height(40px)
  changed = resolve_layout(tree, Vec2{px}(100px, 100px), id)
  @test changed !== first_layout && changed.children[2].top == 40px
end
