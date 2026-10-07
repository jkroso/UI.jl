# Draws the Disk Usage app's icon and saves it as icon.png beside this file:
#
#     julia --project=. examples/disk_usage/icon.jl
#
# The icon is a small sunburst, coloured the way the app colours its own, on a
# white square with round corners. build.jl makes the app's icon from icon.png.
# The sizes follow Apple's grid for Mac app icons: the canvas is 1024 pixels
# square, and the white square is 824 pixels wide in the middle of it.

@use "../27_disk_usage" slice_colour mix
@use "../../Interface/Geometric"...
@use "../../Interface/Specific"...
@use "../../Interface/abstract" describe
@use "../../Interface/draw" draw
@use "../../Interface/save" save_png
@use "github.com/jkroso/Font.jl/units" px
@use Colors: @colorant_str
@use Skia

const CANVAS = 1024
const SQUARE = 824
const CORNER = 185
const HOLE = 0.3          # the radius of the middle, as a fraction of the sunburst's
const RINGS = 3
const THICK = (1 - HOLE) / RINGS
const white = colorant"white"

# Made-up folders, biggest first. A number is a file of that size, and a list is
# a folder of the things in it. All of them get a folder's brighter colours.
const folders = [
  [[8, 4, 2], [6, 3], 6, 4],
  [[7, 5], 6, [3, 1]],
  [[5, 4], 5, 3],
  [[4, 3], 5],
  [[3, 2], 4],
  [4, 2],
]

bytes(file::Number) = file
bytes(folder::Vector) = sum(bytes, folder)

"A Wedge for each thing in `folder`, which spans `a0` to `a1` degrees on ring `ring`"
wedges(folder, ring, a0, a1, hue, mid) = begin
  out = Any[]
  scale = (a1 - a0) / bytes(folder)
  inner = HOLE + (ring - 1) * THICK
  at = a0
  for item in folder
    next = at + bytes(item) * scale
    # Hues as the app picks them: the first ring's go round the circle, and the
    # rings further out take after the folder they're in
    m = (at + next) / 2
    h = mix(hue + 0.25 * (m - mid), m, clamp(2 - ring, 0, 1))
    push!(out, Wedge(width(grow=GrowType.Grow), height(grow=GrowType.Grow), inner=inner, outer=inner + THICK,
                     start=at, sweep=next - at, background(slice_colour(h, ring, true, false)),
                     border(7px, :solid, white)))
    item isa Vector && append!(out, wedges(item, ring + 1, at, next, h, m))
    at = next
  end
  out
end

icon() =
  Box(width(CANVAS * px), height(CANVAS * px), padding(((CANVAS - SQUARE) ÷ 2) * px), Alignment.Center,
    Box(width(SQUARE * px), height(SQUARE * px), padding(64px), radius(CORNER * px), background(white),
      Stack(width(grow=GrowType.Grow), height(grow=GrowType.Grow), wedges(folders, 1, 0.0, 360.0, 0.0, 0.0)...)))

"A soft shadow under the white square, as Apple's icons have"
shadow(ctx) = begin
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, 0x4d000000)  # black at 30%
  blur = Skia.sk_maskfilter_new_blur_with_flags(Skia.SK_BLUR_STYLE_NORMAL, 12f0, true)
  Skia.sk_paint_set_maskfilter(paint, blur)
  edge = Float32((CANVAS - SQUARE) / 2)
  rect = Ref(Skia.sk_rect_t(edge, edge + 12, edge + SQUARE, edge + SQUARE + 12))
  Skia.sk_canvas_draw_round_rect(ctx, rect, Float32(CORNER), Float32(CORNER), paint)
  Skia.sk_maskfilter_unref(blur)
  Skia.sk_paint_delete(paint)
end

save_png(joinpath(@__DIR__, "icon.png"), (CANVAS * px, CANVAS * px), scale=(1.0, 1.0), opaque=false) do ctx, size
  shadow(ctx)
  draw(ctx, size, describe(icon(), size))
end
