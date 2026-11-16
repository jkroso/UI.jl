# Tests for how a font's face is found: by its own name first, and by its
# weight when it has no face of that name. Run them with
# `julia --project=. test.jl fonts`. The fonts they use come with macOS, and
# Source Code Pro is checked only on a Mac that has it.
@use Test: @test, @testset
@use Skia
@use "./fonts" skia_font register_font installed_faces weight_of

weight(f) = Int(f.weight)

@testset "a face is found by its own name" begin
  # Helvetica Neue's UltraLight is lighter than its Thin, so neither is found by its weight's usual name
  names = [f.name for f in installed_faces("Helvetica Neue") if !f.italic && f.width == 5]
  @test "UltraLight" in names && "Thin" in names
  @test weight(skia_font("Helvetica Neue", 14, "UltraLight")) == 100
  @test weight(skia_font("Helvetica Neue", 14, "Thin")) == 200
  @test skia_font("Helvetica Neue", 14, "Light Italic").slant == Skia.SK_FONT_STYLE_SLANT_ITALIC
  # Case and spaces don't matter
  @test weight(skia_font("Helvetica Neue", 14, "ultra light")) == 100
  # A name the font doesn't have gets the weight that the name says
  @test weight(skia_font("Charter", 14, "Bold")) == 700
  @test weight(skia_font("Charter", 14, "Semi Bold")) == 600   # Charter has no Semibold. The weight asked for is kept.
  @test isempty(installed_faces("No Such Font"))
end

@testset "a style name can be another name for a weight" begin
  @test weight_of("UltraLight") == 200
  @test weight_of("Demi Bold Italic") == 600
  @test weight_of("Heavy") == 800
  @test weight_of("Roman") == 400
  @test weight_of("Retina") == 400   # not a weight's name
end

const file = joinpath(homedir(), "Library/Fonts/SourceCodePro-ExtraLight.ttf")
@testset "a loaded font file doesn't take the place of the other weights of an installed font" begin
  if isfile(file) && !isempty(installed_faces("Source Code Pro"))
    register_font(file)
    # The loaded file's weight comes from the file
    @test skia_font("Source Code Pro", 14, "ExtraLight").weight == Skia.SK_FONT_STYLE_WEIGHT_NORMAL
    # Every other weight comes from the installed font
    @test weight(skia_font("Source Code Pro", 14, "Medium")) == 500
    @test weight(skia_font("Source Code Pro", 14, "Light")) == 300
    @test weight(skia_font("Source Code Pro", 14, "")) == 400
  end
end
