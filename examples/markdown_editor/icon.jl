# Draws the Markdown editor's icon and saves it as icon.png beside this file:
#
#     julia --project=. examples/markdown_editor/icon.jl
#
# The icon is a page in the editor's own sepia colours. It has a heading with
# its # showing, a few lines of text and the caret at the end of the last line.
# build.jl makes the app's icon from icon.png. The sizes follow Apple's grid for
# Mac app icons: the canvas is 1024 pixels square, and the page is 824 pixels
# wide in the middle of it.

@use "../../Interface/Geometric"...
@use "../../Interface/Specific"...
@use "../../Interface/abstract" describe WrapMode
@use "../../Interface/draw" draw
@use "../../Interface/save" save_png
@use "github.com/jkroso/Font.jl/units" px
@use Colors: @colorant_str, RGBA

const CANVAS = 1024
const SQUARE = 824
const CORNER = 185
const paper = colorant"rgb(246,240,224)"
const ink = colorant"rgb(60,52,42)"
const pale = colorant"rgb(190,178,152)"
const accent = colorant"rgb(176,100,48)"
const grow = GrowType.Grow
# A soft shadow under the page, as Apple's icons have
const page_shadow = shadow(0, 12, 24, RGBA(0, 0, 0, 0.3))

"A line of text, drawn as a bar. `share` is how much of the page's width it takes, from 0 to 1."
bar(share, colour, tall=46px) = Box(width(percent=share), height(tall), radius(tall / 2), background(colour))

icon() =
  Box(width(CANVAS * px), height(CANVAS * px), padding(((CANVAS - SQUARE) ÷ 2) * px), Alignment.Center,
    Column(width(SQUARE * px), height(SQUARE * px), padding(120px, 110px), radius(CORNER * px), background(paper), page_shadow,
           Alignment.Start, justify=Alignment.Center, child_gap=58px,
      # The heading, with its # showing as it does on the line the caret is in
      Row(width(grow=grow), height(190px), Alignment.Center, child_gap=44px,
        Box(Text("#", size=270px, family="Charter", subfamily="Bold", color=accent, wrap=WrapMode.none)),
        Box(width(grow=grow), height(78px), radius(39px), background(ink))),
      bar(1.0, pale),
      bar(1.0, pale),
      Row(width(grow=grow), height(96px), Alignment.Center, child_gap=22px,
        bar(0.55, pale),
        Box(width(14px), height(96px), radius(7px), background(accent)))))

save_png(joinpath(@__DIR__, "icon.png"), (CANVAS * px, CANVAS * px), scale=(1.0, 1.0), opaque=false) do ctx, size
  draw(ctx, size, describe(icon(), size))
end
