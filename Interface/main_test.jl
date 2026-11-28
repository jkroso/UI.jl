@use Test: @test
@use Test: @testset
@use "../main" => UI
@use "./Geometric" => Geometric
@use "./Specific" => Specific
@use "./abstract" => Abstract
@use "./draw" => Draw
@use "./image" => Images
@use "./fonts" => Fonts
@use "./window" => Window
@use "./save" => Save
@use "./inspector" => InspectorMod
@use "./Semantic" => Semantic
@use "./Semantic/Menu" => Menu
@use "./Semantic/ListTree" => ListTree
@use "./Semantic/Icon" => Icons
@use "./Semantic/SVG" => SVGMod
@use "./Semantic/STLViewer" => STL
@use "./Semantic/Player" => Player
@use "./Semantic/Recorder" => Recorder
@use "./Semantic/Mermaid" => Mermaid
@use "./media" => Media
@use "./objc" => Objc
@use "./testing" => Testing

"Every name `from` exports is the same object here"
same(from) = for name in Base.names(from)
  name === nameof(from) && continue
  @test isdefined(UI, name)
  @test getfield(UI, name) === getfield(from, name)
end

@testset "Interface" begin
  same(Geometric)
  same(Specific)
  same(Abstract) # abstract.jl exports nothing, so this checks the module name only
  same(Draw)
  same(Images)
  same(Fonts)
  same(Window)
  same(Save)
  same(InspectorMod)
  same(Semantic)
  same(Menu)
  same(Icons)
  same(SVGMod)
  same(STL)
  same(Player)
  same(Recorder)

  @test UI.describe === Abstract.describe === Specific.describe
  @test UI.handled === Abstract.handled === Draw.handled
  @test UI.onpinch === Window.onpinch === Draw.onpinch
  @test UI.pause! === Player.pause! === Media.pause!
  @test UI.stop! === Recorder.stop! === Media.stop!
  @test UI.show! === STL.show!
  @test UI.show! !== Mermaid.show!
  @test UI.load! === STL.load!
  @test UI.Item === Menu.Item
  @test UI.Item !== ListTree.Item
  @test UI.ListTree === ListTree.ListTree
  @test UI.skia_cap_height === Specific.skia_cap_height
  @test UI.weight_of === Fonts.weight_of
  @test UI.weight_name === Fonts.weight_name
  @test UI.isitalic === Fonts.isitalic
  @test UI.nswindow === Window.nswindow
  @test UI.load_icon === Icons.load_icon
  @test UI.icon_cache === Icons.icon_cache
  @test UI.popups === Draw.popups
  @test UI.with_round_clip === Draw.with_round_clip
  @test UI.with_clip === Draw.with_clip
  @test UI.Bubble === Draw.Bubble
  @test UI.sync_mouse! === Draw.sync_mouse!
  @test UI.popup_at === Draw.popup_at
  @test UI.frame === Draw.frame
  @test UI.changed! === Draw.changed!
  @test UI.TextInput === Semantic.TextInput
  @test UI.Icon === Semantic.Icon

  @test !isdefined(UI, :libobjc)
  @test !isdefined(UI, :click!)
  @test !isdefined(UI, :silence!)
  @test !isdefined(UI, :play!)
end
