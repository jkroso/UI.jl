@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Window Keys KeyPress onkey
@use "../abstract" SemanticUI describe focus
@use "../Geometric"...
@use "../draw" frame rect
@use "../testing"...
@use "./Inspector" Inspector inspect LeafView CollectionView next_visible
@use "./TextInput" TextInput

@def mutable struct Page <: SemanticUI end
describe(p::Page) = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(10px), child_gap=8px,
                           Alignment.Start, p.children...)

value(ins, label) = first(v for v in ins.firstchild.children if v isa LeafView && v.label == label)

# An edit ends when the keyboard goes anywhere else, and the value keeps what was typed
let settings = Dict{String,Any}("size" => 17, "font" => "Charter"),
    ins = Inspector(inspect(settings, label="settings")),
    other = TextInput(placeholder="Other"),
    w = Window(Page(ins, other), size=(400px, 220px))
  ins.firstchild.collapsed = false
  frame(w)
  size, font = value(ins, "size"), value(ins, "font")

  click!(w, size)
  @test size.editing && w.focus === size.editor
  press!(w, Keys.a, Keys.cmd); type!(w, "21")
  click!(w, other)                                    # a field outside the inspector takes the keyboard
  @test !size.editing && size.editor === nothing
  @test settings["size"] == 21
  @test w.focus === other

  click!(w, size); press!(w, Keys.a, Keys.cmd); type!(w, "22")
  click!(w, font)                                     # another value in the inspector
  @test settings["size"] == 22 && !size.editing
  @test font.editing && w.focus === font.editor

  press!(w, Keys.a, Keys.cmd); type!(w, "Menlo")
  press!(w, Keys.escape)                              # Escape still drops what was typed
  @test !font.editing && settings["font"] == "Charter"
  @test w.focus === ins

  click!(w, size); press!(w, Keys.a, Keys.cmd); type!(w, "big")
  click!(w, other)                                    # text that isn't a number leaves the number as it was
  @test !size.editing && settings["size"] == 22
end

# While a value is being edited, the arrow keys stay in its field. After Escape they move through the inspector.
let settings = Dict{String,Any}("size" => 17, "font" => "Charter", "spelling" => true),
    ins = Inspector(inspect(settings, label="settings")),
    w = Window(Page(ins), size=(400px, 220px))
  ins.firstchild.collapsed = false
  frame(w)
  size = value(ins, "size")
  click!(w, size)
  for key in (Keys.down, Keys.up, Keys.left, Keys.right)
    press!(w, key)
    @test ins.focused === size && size.editing && w.focus === size.editor
    @test !ins.firstchild.collapsed
  end
  press!(w, Keys.escape)
  press!(w, Keys.down)
  @test ins.focused === something(next_visible(size), size)
end

# A string that's being edited keeps its quotes, and the closing one follows the text as it gets longer
let settings = Dict{String,Any}("font" => "Charter"),
    ins = Inspector(inspect(settings, label="settings")),
    w = Window(Page(ins), size=(400px, 120px))
  ins.firstchild.collapsed = false
  frame(w)
  font = value(ins, "font")
  click!(w, font); press!(w, Keys._end)
  quote_after_text() = begin
    before, text, after = rect(font.editor).children
    text.left == before.left + before.width && after.left == text.left + text.width
  end
  @test quote_after_text()
  ends = rect(font.editor).children[3].left
  type!(w, " Bold")
  @test quote_after_text()
  @test rect(font.editor).children[3].left > ends
  @test font.editor.scroll == 0px
end

# Escape that ends an edit leaves the keyboard with the inspector, so the arrow keys move through it again.
# The next Escape goes on to the page it's in, which takes the keyboard back, as Kaydown's page does.
@def mutable struct Host <: SemanticUI end
describe(h::Host) = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(10px), Alignment.Start, h.children...)
onkey(h::Host, e::KeyPress{Keys.escape}) = (e.window.focus !== h && focus(h); nothing)

let settings = Dict{String,Any}("recent" => ["welcome.md", "components.md"]),
    ins = Inspector(inspect(settings, label="settings")),
    host = Host(ins),
    w = Window(host, size=(400px, 160px))
  ins.firstchild.collapsed = false
  frame(w)
  recent = first(v for v in ins.firstchild.children if v isa CollectionView)
  click!(w, recent)
  first_name, second_name = (v for v in recent.children if v isa LeafView)
  click!(w, first_name)
  press!(w, Keys.escape)
  @test !first_name.editing && w.focus === ins
  press!(w, Keys.down)
  @test ins.focused === second_name
  press!(w, Keys.escape)
  @test w.focus === host
end
