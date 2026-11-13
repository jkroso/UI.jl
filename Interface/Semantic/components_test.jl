@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "../abstract" SemanticUI describe integrate light dark with_theme
@use "../Geometric"...
@use "../draw" frame rect popups
@use "../testing"...
@use "."...
@use "./ListTree" => Tree
@use Colors: HSV

# Every component, in one window, in each theme: lay each one out, draw it, put the mouse on it and click it
@def mutable struct Gallery <: SemanticUI
  dark::Bool = false
end
describe(g::Gallery) = with_theme(g.dark ? dark : light) do
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(10px), child_gap=6px, Alignment.Start, g.children...)
end

let tree = ListTree(ItemGroup("Cars", Tree.Item("Fast"), Tree.Item("Slow"))),
    gallery = Gallery(
      Button("Press", onclick=_ -> nothing), ButtonGroup(Button("A"), Button("B")), TextInput(), Checkbox(label="Tick"), Toggle(),
      Slider(value=0.5, format=v -> round(v, digits=1)), ProgressBar(value=0.4), RadioGroup(labels=["One", "Two"]),
      Select(options=["x", "y"]), Dropdown(options=["x", "y"]), Tooltip("Hover", "A tip"), KeyCombo(:S, :cmd),
      Table(TableHeader("Name", "Price"), TableRow("Pen", "\$2")), tree, ColorPicker(color=HSV(225, 0.8, 0.8)),
      Inspector(inspect(Dict(:a => 1, :b => [true, "two"]), label="data")), Icon("search"), Link(_ -> Box(Text("Link")), "https://example.com"))
  w = Window(gallery, size=(420px, 1400px))
  for theme in (false, true)
    gallery.dark = theme
    frame(w)
    for node in gallery.children
      @test rect(node) !== nothing
      move!(w, node)
      node isa Link || click!(w, node)       # a click on the link would open a browser
      press!(w, Keys.escape)                 # close a menu, if the click opened one
      @test isempty(popups(w)) || all(p -> !p.input, popups(w))
    end
  end
  @test !integrate(gallery.children[4])      # the checkbox was clicked once in each theme, so it's clear again
  @test !integrate(gallery.children[5])      # and so was the switch
end
