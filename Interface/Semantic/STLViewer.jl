@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse onscroll flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI WrapMode describe focus theme scale handled sized
@use "../draw" draw cursor redraw_in! MouseScroll
@use Colors: Colorant, RGB, @colorant_str
@use "./ThreeMF" => ThreeMF

# An STL file holds the surface of a solid as a list of triangles. It's the
# file that a 3D printer's program reads. The viewer shows the solid with light
# on it, and you turn it with the mouse:
#
#     STLViewer("bracket.stl")
#
# It shows a 3MF file too, the file that a slicer saves: `STLViewer("bracket.3mf")`.
#
# Drag to turn the model. Hold ⌘ and scroll to make it bigger or smaller.
# Click it twice to see it as it was at first.

const Vec = NTuple{3,Float32}

dot(a::Vec, b::Vec) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
cross(a::Vec, b::Vec) = (a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
unit(a::Vec) = a ./ sqrt(dot(a, a))

"""
The triangles of a model. They're moved and scaled so that the model fits in a
ball of radius 1 round the origin, whatever size it has in its file.
"""
struct Mesh
  corners::Vector{Vec}   # three for each triangle
  normals::Vector{Vec}   # one for each triangle: the way its face points
  size::Vec              # how wide, deep and tall the model is, in the units of its file
end

"The triangles among `points` that have an area, and the way each one faces. A triangle with no area doesn't show."
faces(points::Vector{Vec}) = begin
  corners, normals = sizehint!(Vec[], length(points)), sizehint!(Vec[], length(points) ÷ 3)
  for i in 1:3:length(points)-2
    a, b, c = points[i], points[i+1], points[i+2]
    n = cross(b .- a, c .- a)
    len = sqrt(dot(n, n))
    len > 0 || continue
    push!(corners, a, b, c)
    push!(normals, n ./ len)
  end
  corners, normals
end

Mesh(points::Vector{Vec}) = begin
  length(points) >= 3 || error("The file has no triangles")
  lo = reduce((a, b) -> min.(a, b), points)
  hi = reduce((a, b) -> max.(a, b), points)
  middle = (lo .+ hi) ./ 2
  reach = sqrt(maximum(p -> dot(p .- middle, p .- middle), points))
  reach > 0 && isfinite(reach) || error("The model has no size")
  Mesh(faces(map!(p -> (p .- middle) ./ reach, points, points))..., hi .- lo)
end

triangles(m::Mesh) = length(m.normals)

# A frame has to draw every triangle of a model, and a model can have millions.
# So a big model has a rougher copy that's drawn while it turns. The model
# itself is drawn when it stops.
const MOST = 250_000   # the most triangles that are drawn while a model turns

"""
A copy of `m` with about `most` triangles or fewer. Each corner moves to the
nearest point of a grid, and a triangle shows only if its corners are still
three different points. It keeps the way it faced, so the light on it doesn't
change.
"""
rough(m::Mesh, most=MOST) = begin
  cells = 256f0   # points of the grid in a length of 1
  while true
    corners, normals = snapped(m, cells)
    (length(normals) <= most || cells <= 16) && return Mesh(corners, normals, m.size)
    # A grid with half as many points in a length leaves about a quarter of the triangles
    cells = max(16f0, floor(cells * sqrt(0.85f0 * most / length(normals))))
  end
end

"The triangles of `m` that still have three different corners when each corner moves to a grid with `cells` points in a length of 1"
snapped(m::Mesh, cells::Float32) = begin
  corners, normals = Vec[], Vec[]
  snap(p) = round.(p .* cells) ./ cells
  for t in eachindex(m.normals)
    a, b, c = snap(m.corners[3t-2]), snap(m.corners[3t-1]), snap(m.corners[3t])
    (a == b || b == c || a == c) && continue
    push!(corners, a, b, c)
    push!(normals, m.normals[t])
  end
  corners, normals
end

"""
The corners of the triangles in an STL file, three for each triangle. The file
is in one of two forms. The binary form says how many triangles it has, then
gives 50 bytes for each. The text form names each corner in a line like
`vertex 1.0 2.5 0.0`.
"""
points(bytes::Vector{UInt8}) = begin
  n = length(bytes) >= 84 ? Int(GC.@preserve bytes ltoh(unsafe_load(Ptr{UInt32}(pointer(bytes, 81))))) : 0
  # Some binary files start with the word that starts a text file, so the length is what tells them apart
  length(bytes) == 84 + 50n && return binary(bytes, n)
  found = ascii(bytes)
  isempty(found) && n > 0 && length(bytes) > 84 + 50n && return binary(bytes, n)
  found
end

binary(bytes, n) = begin
  out = Vector{Vec}(undef, 3n)
  GC.@preserve bytes for i in 0:n-1
    # Each triangle is 12 numbers of 4 bytes: the way it faces, then its three corners
    at = Ptr{Float32}(pointer(bytes, 85 + 50i + 12))
    for corner in 0:2
      out[3i + corner + 1] = ntuple(k -> ltoh(unsafe_load(at, 3corner + k)), 3)
    end
  end
  out
end

ascii(bytes) = [ntuple(k -> parse(Float32, m[k]), 3) for m in eachmatch(r"vertex\s+(\S+)\s+(\S+)\s+(\S+)", String(copy(bytes)))]

"The model in the STL file at `path`, or a sentence that says why there isn't one"
read_stl(path) = begin
  isfile(path) || return "There's no file at $path"
  try
    Mesh(points(read(path)))
  catch
    "$(basename(path)) isn't an STL file that can be read"
  end
end

"The model in the 3MF file at `path`, or a sentence that says why there isn't one"
read_3mf(path) = begin
  isfile(path) || return "There's no file at $path"
  try
    Mesh(ThreeMF.points(path))
  catch
    "$(basename(path)) isn't a 3MF file that can be read"
  end
end

"The model in the file at `path`: a 3MF file if its name ends in .3mf, and an STL file if not"
read_model(path) = lowercase(splitext(path)[2]) == ".3mf" ? read_3mf(path) : read_stl(path)

# --- the picture ---------------------------------------------------------------
#
# The model is drawn a triangle at a time into a grid of pixels. A second grid
# holds how near the eye each pixel's surface is, so a triangle only shows
# where nothing nearer has been drawn. Skia then draws the grid as an image.

const EYE = 4f0                                      # how far the eye is from the middle of the model, whose ball has radius 1
const KEY_LIGHT = unit((-0.45f0, 0.6f0, 0.66f0))     # from above the eye, to its left
const FILL_LIGHT = unit((0.7f0, -0.25f0, 0.4f0))     # a weaker one from the right, so the shaded side isn't flat

"The last picture of a model, kept so that a frame in which nothing changed draws it again"
mutable struct Picture
  image::Ptr{Skia.sk_image_t}
  of::Any                    # what it's a picture of: the model, how it's turned, its colour and the picture's size
  pixels::Vector{UInt32}     # 0xAARRGGBB each, a row at a time from the top
  depth::Vector{Float32}     # 1 ÷ the distance from the eye to the surface at each pixel, or 0 where there's none
  Picture() = finalizer(release!, new(C_NULL, nothing, UInt32[], Float32[]))
end

release!(p::Picture) = (p.image == C_NULL || Skia.sk_image_unref(p.image); p.image = C_NULL; nothing)

"""
The three axes of the eye, in the model's space: right, up and towards the eye.
`turn` is how far the model is turned round its upright axis, which is z in an
STL file. `tilt` is how far above the model the eye is. Both are in degrees.
"""
sight(turn, tilt) = begin
  s, c = Float32.(sincosd(turn))
  st, ct = Float32.(sincosd(tilt))
  right = (c, -s, 0f0)
  back = (s, c, 0f0)   # the way the eye looks, before it's tilted
  up = (0f0, 0f0, 1f0)
  (right, ct .* up .+ st .* back, st .* up .- ct .* back)
end

"0xAARRGGBB for a colour with light of strength `light` on it"
lit(colour::Vec, light) = begin
  channel(x) = round(UInt32, 255 * clamp(x * light, 0f0, 1f0))
  0xff000000 | channel(colour[1]) << 16 | channel(colour[2]) << 8 | channel(colour[3])
end

"""
Draw `mesh` into `pixels`, a picture `w` pixels wide and `h` tall. `(cx, cy)` is
the pixel where the middle of the model goes. `focal` is how many pixels wide a
length of 1 is when it's 1 away from the eye. Pixels with no model on them are
left clear.
"""
function render!(pixels::Vector{UInt32}, depth::Vector{Float32}, w::Int, h::Int, mesh::Mesh,
                 (right, up, near)::NTuple{3,Vec}, focal::Float32, cx::Float32, cy::Float32, colour::Vec)
  fill!(pixels, 0x00000000)
  fill!(depth, 0f0)
  corners, normals = mesh.corners, mesh.normals
  # The lights keep their places beside the eye, so here they're put in the model's space
  towards(light) = right .* light[1] .+ up .* light[2] .+ near .* light[3]
  key, soft = towards(KEY_LIGHT), towards(FILL_LIGHT)
  @inbounds for t in eachindex(normals)
    a, b, c = corners[3t-2], corners[3t-1], corners[3t]
    # 1 ÷ how far each corner is from the eye, then where it is in the picture
    ia, ib, ic = 1 / (EYE - dot(near, a)), 1 / (EYE - dot(near, b)), 1 / (EYE - dot(near, c))
    ax, ay = cx + focal * dot(right, a) * ia, cy - focal * dot(up, a) * ia
    bx, by = cx + focal * dot(right, b) * ib, cy - focal * dot(up, b) * ib
    qx, qy = cx + focal * dot(right, c) * ic, cy - focal * dot(up, c) * ic
    # The pixels whose middles are in the box round the triangle
    x0, x1 = max(0, ceil(Int, min(ax, bx, qx) - 0.5f0)), min(w - 1, floor(Int, max(ax, bx, qx) - 0.5f0))
    y0, y1 = max(0, ceil(Int, min(ay, by, qy) - 0.5f0)), min(h - 1, floor(Int, max(ay, by, qy) - 0.5f0))
    (x0 > x1 || y0 > y1) && continue
    area = (bx - ax) * (qy - ay) - (qx - ax) * (by - ay)
    area == 0 && continue
    # The light on the face. A face is lit on the side that the eye sees, whichever way the file says it points.
    n = normals[t]
    facing = dot(n, near) * EYE - dot(n, a)
    n = facing < 0 ? .-n : n
    shade = lit(colour, 0.3f0 + 0.62f0 * max(0f0, dot(n, key)) + 0.16f0 * max(0f0, dot(n, soft)))
    # How much of each corner a pixel has: three weights that add up to 1. Each
    # changes by a fixed step from a pixel to the next one, and so does the depth.
    k = 1 / area
    ua, va = (by - qy) * k, (qx - bx) * k
    ub, vb = (qy - ay) * k, (ax - qx) * k
    x, y = x0 + 0.5f0, y0 + 0.5f0
    wa = ((bx - x) * (qy - y) - (qx - x) * (by - y)) * k
    wb = ((qx - x) * (ay - y) - (ax - x) * (qy - y)) * k
    d = wa * ia + wb * ib + (1 - wa - wb) * ic
    ud, vd = ua * (ia - ic) + ub * (ib - ic), va * (ia - ic) + vb * (ib - ic)
    for row in y0:y1
      pa, pb, pd = wa, wb, d
      i = row * w + x0
      for _ in x0:x1
        i += 1
        if pa >= 0 && pb >= 0 && pa + pb <= 1 && pd > depth[i]
          depth[i] = pd
          pixels[i] = shade
        end
        pa += ua; pb += ub; pd += ud
      end
      wa += va; wb += vb; d += vd
    end
  end
  pixels
end

"How many of the screen's pixels a px is wide on the canvas `ctx`"
density(ctx) = begin
  m = Ref(Skia.sk_matrix_t(1f0, 0f0, 0f0, 0f0, 1f0, 0f0, 0f0, 0f0, 1f0))
  Skia.sk_canvas_get_total_matrix(ctx, m)
  sqrt(abs(m[].scaleX * m[].scaleY - m[].skewX * m[].skewY))
end

const smooth = Skia.sk_sampling_options_t(0, false, Skia.sk_cubic_resampler_t(0f0, 0f0),
                                          Skia.SK_FILTER_MODE_LINEAR, Skia.SK_MIPMAP_MODE_NONE)

# --- the component -------------------------------------------------------------

const SMALLEST, BIGGEST = 0.4, 12.0

@def mutable struct STLViewer <: SemanticUI
  path::String = ""
  turn::Float64 = 35.0                # degrees round the model's upright axis
  tilt::Float64 = 22.0                # degrees the eye is above the model. At 90 it looks straight down.
  zoom::Float64 = 1.0                 # 1 fits the whole model in the view however it's turned
  height::px = 340px                  # of the view. The viewer is as wide as it's given room for.
  color::Colorant = colorant"rgb(132,160,196)"
  # What it remembers between frames
  model::Any = nothing                # the Mesh of the file, or a sentence that says why there isn't one
  rough::Any = nothing                # a Mesh with fewer triangles to draw while a big model turns, or nothing for a small one
  moved::Float64 = 0.0                # when it was last turned or made bigger or smaller
  home::Any = nothing                 # the turn, tilt and zoom it was made with, which two clicks put back
  read::Float64 = -1.0                # when the file had last changed, the last time it was read
  grab::Any = nothing                 # where the mouse was on the last move of a drag
  clicked::Float64 = 0.0              # when it was last clicked, to tell a double click
  picture::Picture = Picture()
end

"`STLViewer(\"part.stl\")` shows the model in that file. A path that isn't absolute starts from the folder that Julia is in now."
STLViewer(path::AbstractString; kwargs...) = STLViewer(; path=abspath(path), kwargs...)

"Read the file, if it hasn't been read or has changed since"
load!(v::STLViewer) = begin
  changed = mtime(v.path)
  v.model !== nothing && changed == v.read && return v.model
  v.read = changed
  v.model = read_model(v.path)
  v.rough = v.model isa Mesh && triangles(v.model) > MOST ? rough(v.model) : nothing
  v.model
end

const SETTLE = 0.2   # seconds after a big model last moved until the model itself is drawn

"Is a big model still moving? Its rougher copy is drawn while it is."
turning(v::STLViewer) = v.rough !== nothing && time() - v.moved < SETTLE
"Note that the model moved just now"
moved!(v::STLViewer) = (v.moved = time(); v)

"A count with a comma between each three digits, like 12,480"
commas(n::Integer) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")
"A length with no more digits than it needs to tell it from one that's a little different"
short(x) = x >= 100 ? string(round(Int, x)) : string(round(x, sigdigits=3))

"What the line under the view says of the model: how many triangles it has, and how wide, deep and tall it is"
about(m::Mesh) = "$(commas(triangles(m))) triangle$(triangles(m) == 1 ? "" : "s")  ·  $(join(short.(m.size), " × "))"
about(::Any) = ""

describe(v::STLViewer) = begin
  t, k = theme(v), scale(theme(v))
  model = load!(v)
  v.home === nothing && (v.home = (v.turn, v.tilt, v.zoom))
  # A big model that has just stopped needs one more frame, to draw the model itself
  turning(v) && redraw_in!(v, SETTLE / 2)
  grow = GrowType.Grow
  Column(width(grow=grow), radius(8px), border(1px, :solid, t.line), background(t.surface), clip=true,
    Box(width(grow=grow), height(v.height), padding(16px),
      (model isa Mesh ? () : (Text(String(model), size=sized(12pt, t), color=t.dim),))...),
    Row(width(grow=grow), padding(12px, 7px), child_gap=12px, background(t.hover), radius(0px, 7px),
      Text(basename(v.path), size=sized(12pt, t), color=t.text, wrap=WrapMode.none),
      Box(width(grow=grow)),
      Text(about(model), size=sized(12pt, t), color=t.dim, wrap=WrapMode.none)))
end

draw(ctx, size, ui::ConcreteRect, v::STLViewer) = begin
  v.model isa Mesh || return
  mesh = turning(v) ? v.rough : v.model
  area = ui.children[1]
  # Four samples across each px on a screen with 2 pixels to the px, so that
  # the model's edges are smooth. Never fewer than 2, for a canvas like a PDF's.
  detail = clamp(2density(ctx), 2, 4)
  w, h = round(Int, area.width.value * detail), round(Int, area.height.value * detail)
  (w < 1 || h < 1) && return
  p = v.picture
  colour = convert(RGB{Float32}, v.color)
  of = (mesh, v.turn, v.tilt, v.zoom, colour, w, h)
  if p.of != of
    length(p.pixels) == w * h || (p.pixels = Vector{UInt32}(undef, w * h); p.depth = Vector{Float32}(undef, w * h))
    # The ball round the model shows `fit` pixels wide at a zoom of 1: a little less than the view's short side
    fit = 0.48f0 * min(w, h)
    focal = Float32(fit * v.zoom) * sqrt(EYE^2 - 1)
    render!(p.pixels, p.depth, w, h, mesh, sight(v.turn, v.tilt), focal, w / 2f0, h / 2f0, (colour.r, colour.g, colour.b))
    release!(p)
    info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_BGRA_8888, Skia.SK_ALPHA_TYPE_PREMUL, w, h))
    pixels = p.pixels
    GC.@preserve info pixels begin
      data = Skia.sk_data_new_with_copy(pointer(pixels), UInt64(4w * h))
      p.image = Skia.sk_image_new_raster_data(info, data, Csize_t(4w))
      Skia.sk_data_unref(data)
    end
    p.of = of
  end
  p.image == C_NULL && return
  from = Ref(Skia.sk_rect_t(0f0, 0f0, Float32(w), Float32(h)))
  to = Ref(Skia.sk_rect_t(flt(area.left), flt(area.top), flt(area.left + area.width), flt(area.top + area.height)))
  # A model that's bigger than the view stops inside the viewer's border and its round corners
  edge = Ref(Skia.sk_rect_t(flt(ui.left + 1px), flt(ui.top + 1px), flt(ui.left + ui.width - 1px), flt(ui.top + ui.height - 1px)))
  clip = Skia.sk_path_new()
  Skia.sk_path_add_rounded_rect(clip, edge, flt(7px), flt(7px), Skia.SK_PATH_DIRECTION_CW)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_canvas_save(ctx)
  Skia.sk_canvas_clip_path_with_operation(ctx, clip, Skia.SK_CLIP_OP_INTERSECT, true)
  Skia.sk_canvas_draw_image_rect(ctx, p.image, from, to, Ref(smooth), paint, Skia.SRC_RECT_CONSTRAINT_FAST)
  Skia.sk_canvas_restore(ctx)
  Skia.sk_paint_delete(paint)
  Skia.sk_path_delete(clip)
end

# --- the mouse -----------------------------------------------------------------

cursor(::STLViewer) = :hand

"Show the model as it was at first"
reset!(v::STLViewer) = ((v.turn, v.tilt, v.zoom) = v.home; moved!(v))

onkey(v::STLViewer, e::KeyPress{Keys.mouse_left}) = begin
  focus(v)
  now = time()
  now - v.clicked < 0.4 && v.home !== nothing && reset!(v)
  v.clicked = now
  v.grab = e.window.mouse
  handled
end

# A drag turns the model: half a degree for each px. Up and down tilt it, as far as the top and the underside.
onmouse(v::STLViewer, e::MouseMove) = begin
  (Keys.mouse_left in e.window.keys && v.grab !== nothing) || (v.grab = nothing; return)
  dx, dy = (e.position[1] - v.grab[1]).value, (e.position[2] - v.grab[2]).value
  v.grab = e.position
  v.turn = mod(v.turn + dx / 2, 360)
  v.tilt = clamp(v.tilt + dy / 2, -90, 90)
  (dx == 0 && dy == 0) || (v.clicked = 0.0; moved!(v))   # a click that moved isn't half of a double click
  handled   # the drag is the viewer's, so the nodes above don't act on it too
end

# Scrolling with ⌘ held makes the model bigger or smaller. Without ⌘ it scrolls the page that the viewer is on.
onscroll(v::STLViewer, e::MouseScroll) = begin
  Keys.cmd in e.window.keys || return
  v.zoom = clamp(v.zoom * exp(e.delta[2].value / 10), SMALLEST, BIGGEST)
  moved!(v)
  handled
end

# The arrow keys turn it too, once a click has given it the keyboard
onkey(v::STLViewer, ::KeyPress{Keys.left}) = (v.turn = mod(v.turn - 10, 360); moved!(v); handled)
onkey(v::STLViewer, ::KeyPress{Keys.right}) = (v.turn = mod(v.turn + 10, 360); moved!(v); handled)
onkey(v::STLViewer, ::KeyPress{Keys.up}) = (v.tilt = clamp(v.tilt + 10, -90, 90); moved!(v); handled)
onkey(v::STLViewer, ::KeyPress{Keys.down}) = (v.tilt = clamp(v.tilt - 10, -90, 90); moved!(v); handled)

export STLViewer, Mesh, read_stl, read_3mf, read_model
