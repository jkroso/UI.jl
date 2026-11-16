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
@use "./draw" show_menu! popup! popups hide_menu! show_tooltip! close_popup! arrow_point
"Something to click in a popup"
@def mutable struct Hit <: SemanticUI end
describe(::Hit) = Box(width(grow=GrowType.Grow), height(30px))
const hits = Int[]
onkey(::Hit, ::KeyPress{Keys.mouse_left}) = (push!(hits, 1); handled)
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

  # A menu that's taller than the window stays in it, on the side with more room, and scrolls to the rest
  many = ["Item $i" for i in 1:30]
  show_menu!(w, many, 100px, 30px, 120px); frame(w)
  tall = only(popups(w)).scene
  @test tall.top == 30px && tall.top + tall.height <= 200px
  mouse(150, 100)
  onscroll(w, Vec2{px}(0px, -2px)); frame(w)
  list = only(popups(w)).content
  @test list.scroll.offset == 60px
  frame(w); frame(w)
  @test list.scroll.offset == 60px   # it stays scrolled
  hide_menu!(w)
  show_menu!(w, many, 100px, 170px, 120px); frame(w)
  above = only(popups(w)).scene
  @test above.top >= 4px && above.top + above.height <= 170px
  hide_menu!(w)
  show_menu!(w, many, 100px, 1px, 120px); frame(w)   # 6 items have room under it, so it goes there though there's none above
  @test only(popups(w)).scene.top == 1px
  hide_menu!(w)
  show_menu!(w, many, 100px, 170px, 120px); frame(w)
  list = only(popups(w)).content
  foreach(_ -> press(Keys.down), 1:12)
  @test list.active == 12 && list.scroll.offset >= 12 * 32px - list.scroll.viewport   # the arrows keep the item in sight
  hide_menu!(w)
  # The words of an item that's too long stop at the edge of the menu
  show_menu!(w, ["A name that is much too long for a menu this narrow"], 100px, 30px, 120px); frame(w)
  narrow = only(popups(w)).scene
  @test narrow.width == 120px
  hide_menu!(w)

  # A tooltip is beside its target, the mouse goes through it, and the next mouse move takes it away
  show_tooltip!(w, Box(padding(8px, 5px), Text("Save")), 100px, 100px, 40px, 20px, placement=:bottom); frame(w)
  tip = only(popups(w)).scene
  @test tip.top == 124px && tip.left + tip.width / 2 == 120px
  @test hittest(w, Vec2{px}(120px, 130px)) isa Page        # the page behind it, not the tooltip
  mouse(10, 150)
  @test isempty(popups(w))

  # A popup that isn't modal takes the mouse over it and no more: a click outside goes to the app, and it stays open
  popup!(w, Hit(), anchor=(100px, 100px, 40px, 20px), placement=:bottom, width=80px, key=:found, modal=false); frame(w)
  found = only(popups(w)).scene
  click(found.left.value + 5, found.top.value + 5)
  @test hits == [1] && length(popups(w)) == 1
  click(50, 18)                                      # on the dropdown behind it, which opens its menu
  @test dropdown.open && any(p -> p.key == :found, popups(w))
  press(Keys.escape)                                 # closes the menu, and not the list
  @test !dropdown.open && only(popups(w)).key == :found
  close_popup!(w, :found); frame(w)

  # A tooltip beside something at the edge of the window moves in to stay whole, on the left and on the right
  words = Box(padding(8px, 5px), Text("Count things on the plan"))
  show_tooltip!(w, words, 2px, 100px, 20px, 20px, placement=:bottom); frame(w)
  @test only(popups(w)).scene.left == 4px
  show_tooltip!(w, words, 280px, 100px, 20px, 20px, placement=:bottom); frame(w)
  tip = only(popups(w)).scene
  @test tip.left + tip.width == 296px
  # One with no room under its target goes over it, and comes back under a target at the top
  show_tooltip!(w, words, 100px, 180px, 40px, 16px, placement=:bottom); frame(w)
  tip = only(popups(w))
  @test tip.scene.top + tip.scene.height == 176px && tip.content.placement == :top
  show_tooltip!(w, words, 100px, 2px, 40px, 16px, placement=:top); frame(w)
  tip = only(popups(w))
  @test tip.scene.top == 22px && tip.content.placement == :bottom
  # One at the side of its target moves in from the top of the window
  show_tooltip!(w, words, 100px, 0px, 40px, 10px, placement=:right); frame(w)
  @test only(popups(w)).scene.top == 4px
  # The arrow of one beside its target is in line with the target's middle, which is the tooltip's middle
  show_tooltip!(w, Box(padding(8px, 5px), Text("Show transcription", size=12px)), 100px, 100px, 24px, 24px, placement=:right); frame(w)
  tip = only(popups(w))
  @test tip.scene.height < 22px   # too short to keep the arrow clear of its corners
  @test arrow_point(tip.content, tip.scene)[2] == 112px
  @test tip.scene.top + tip.scene.height / 2 == 112px
  mouse(10, 150)
end

# A tooltip of a node goes under the node as it is in the frame that shows the tooltip.
# This one gets wider when the mouse is over it, on the frame after the mouse comes.
"Something that's wider with the mouse over it, and shows a tooltip"
@def mutable struct Widens <: SemanticUI end
describe(g::Widens) = Box(width(ishovered(g) ? 200px : 120px), height(20px))
onmouse(g::Widens, e::MouseMove) = show_tooltip!(e.window, Box(padding(8px, 5px), Text("Wide")), g, placement=:bottom)
let w = Window(Page(Widens()), size=(300px, 200px))
  frame(w)
  node = w.ui.firstchild
  @test rect(node).width == 120px
  pos = Vec2{px}(10px, 10px)
  onmouse(w, MouseMove(pos, w)); w.mouse = pos; frame(w)
  @test rect(node).width == 200px
  tip = only(popups(w))
  @test tip.scene.left + tip.scene.width / 2 == 100px
  @test arrow_point(tip.content, tip.scene)[1] == 100px
  close_popup!(w, :tooltip)
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

# Files that are dropped on a window go to the app that the window shows
@use "github.com/jkroso/MiniFB.jl" onfiledrop
@def mutable struct Tray <: SemanticUI
  files::Vector{String} = String[]
end
describe(t::Tray) = Box(width(100px), height(100px))
onfiledrop(t::Tray, w::Window, paths) = append!(t.files, paths)
let tray = Tray(), w = Window(tray, size=(100px, 100px))
  frame(w)
  onfiledrop(w, ["/tmp/a.png", "/tmp/b.md"])
  @test tray.files == ["/tmp/a.png", "/tmp/b.md"]
  # An app that doesn't take files leaves them
  @test onfiledrop(Window(Box(width(10px)), size=(100px, 100px)), ["/tmp/a.png"]) === nothing
end

# A window that closes tells the app that it shows, and what was kept for the window is forgotten.
# A window that isn't on the screen is closed as soon as it's asked to close.
@use "github.com/jkroso/MiniFB.jl" onclose
@use "./draw" scene popups
@def mutable struct Shop <: SemanticUI
  closed::Int = 0
end
describe(s::Shop) = Box(width(100px), height(100px))
onclose(s::Shop, w::Window) = (s.closed += 1)
let shop = Shop(), w = Window(shop, size=(100px, 100px))
  frame(w)
  show_tooltip!(w, Box(padding(8px, 5px), Text("Open")), shop, placement=:bottom)
  frame(w)
  @test scene(w) !== nothing && !isempty(popups(w))
  @test !isopen(w)   # it was never on the screen
  close(w)
  @test shop.closed == 1
  @test scene(w) === nothing && isempty(popups(w))
end
