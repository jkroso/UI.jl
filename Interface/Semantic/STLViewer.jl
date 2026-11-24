@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse onscroll flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"...
@use "../abstract" SemanticUI WrapMode describe focus theme scale handled sized
@use "../draw" draw cursor rect redraw_in! MouseScroll Pinch onpinch
@use Colors: Colorant, RGB, @colorant_str
@use "./ThreeMF" => ThreeMF
@use "./GLTF" => GLTF

# An STL file holds the surface of a solid as a list of triangles. It's the
# file that a 3D printer's program reads. The viewer shows the solid with light
# on it, and you turn it with the mouse:
#
#     STLViewer("bracket.stl")
#
# It shows a 3MF file too, the file that a slicer saves: `STLViewer("bracket.3mf")`.
#
# A glTF file, which ends in .glb or .gltf, also says what the surface is made
# of. The viewer shows it with its own colours, metals and pictures, in the
# light of a studio: `STLViewer("satellite.glb")`.
#
# Drag to turn the model. Hold ⌘ and scroll to make it bigger or smaller. It
# grows towards the mouse, so you can go close to one part of it, and a drag
# then turns it round that part. Click it twice to see it as it was at first.
#
# `STLViewer("bracket.stl", fill=true)` takes all the room that it's given and
# has no frame. That's for a window that shows nothing but the model.

const Vec = NTuple{3,Float32}
const UV = NTuple{2,Float32}

dot(a::Vec, b::Vec) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
cross(a::Vec, b::Vec) = (a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
unit(a::Vec) = a ./ sqrt(dot(a, a))

# --- what a surface is made of -------------------------------------------------

"One size of a picture that's wrapped round a model"
struct Level
  w::Int
  h::Int
  pixels::Vector{UInt32}   # 0xAABBGGRR each, a row at a time from the top
end

"""
A picture that's wrapped round a model: at its own size, then at half of that,
and so on down to one pixel. A surface that's far off reads a small one, so
that it doesn't sparkle as it turns.
"""
struct Texture
  levels::Vector{Level}
  bits::Float32   # log2 of how many pixels wide it is, taken as a square
end

"The mean of four pixels, a channel at a time"
mean(a::UInt32, b::UInt32, c::UInt32, d::UInt32) = begin
  odd, even = 0x00ff00ff, 0xff00ff00
  lo = ((a & odd) + (b & odd) + (c & odd) + (d & odd) + 0x00020002) >> 2 & odd
  hi = (((a & even) >> 2) + ((b & even) >> 2) + ((c & even) >> 2) + ((d & even) >> 2)) & even
  lo | hi
end

"A picture half as wide and half as tall, each pixel the mean of four"
half(l::Level) = begin
  w, h = max(1, l.w ÷ 2), max(1, l.h ÷ 2)
  out = Vector{UInt32}(undef, w * h)
  @inbounds for y in 0:h-1, x in 0:w-1
    x1, y1 = min(2x + 1, l.w - 1), min(2y + 1, l.h - 1)
    out[y*w+x+1] = mean(l.pixels[2y*l.w+2x+1], l.pixels[2y*l.w+x1+1], l.pixels[y1*l.w+2x+1], l.pixels[y1*l.w+x1+1])
  end
  Level(w, h, out)
end

const WIDEST = 4096   # pixels of a picture that are kept. A view can't show more.

"The picture in `bytes`, a PNG or a JPEG. One that can't be read has no levels."
Texture(bytes::Vector{UInt8}) = begin
  none = Texture(Level[], 0f0)
  isempty(bytes) && return none
  data = GC.@preserve bytes Skia.sk_data_new_with_copy(pointer(bytes), UInt64(length(bytes)))
  image = Skia.sk_image_new_from_encoded(data)
  Skia.sk_data_unref(data)
  image == C_NULL && return none
  w, h = Int(Skia.sk_image_get_width(image)), Int(Skia.sk_image_get_height(image))
  pixels = Vector{UInt32}(undef, w * h)
  info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_RGBA_8888, Skia.SK_ALPHA_TYPE_UNPREMUL, w, h))
  ok = GC.@preserve info pixels Skia.sk_image_read_pixels(image, pointer_from_objref(info), pointer(pixels), Csize_t(4w),
                                                         Cint(0), Cint(0), Skia.sk_image_caching_hint_t(0))
  Skia.sk_image_unref(image)
  (ok && w > 0 && h > 0) || return none
  levels = [Level(w, h, pixels)]
  while last(levels).w > 1 || last(levels).h > 1; push!(levels, half(last(levels))) end
  while length(levels) > 1 && max(first(levels).w, first(levels).h) > WIDEST; popfirst!(levels) end
  Texture(levels, log2(Float32(first(levels).w) * first(levels).h) / 2)
end

"""
How the surface of a model looks, when its file says. A list has something for
each corner or each triangle of the model. `normals`, `places` and `tints` are
empty when the file doesn't give them.
"""
struct Look
  normals::Vector{Vec}               # the way the surface faces at each corner, so that a curve looks smooth
  places::Vector{UV}                 # where each corner is in the pictures of its material
  tints::Vector{Vec}                 # a colour for each corner
  made_of::Vector{Int32}             # which of `materials` each triangle is made of
  materials::Vector{GLTF.Material}
  textures::Vector{Texture}          # the file's pictures
end

"`paint`, or no picture if `textures` doesn't have the one that it names"
readable(paint::GLTF.Paint, textures) = 1 <= paint.image <= length(textures) && !isempty(textures[paint.image].levels) ? paint : GLTF.BARE
"`m` without the pictures that couldn't be read"
readable(m::GLTF.Material, textures) = begin
  ok(p) = readable(p, textures)
  GLTF.Material(m.colour, m.metal, m.rough, m.glow, ok(m.base), ok(m.surface), ok(m.glowing), ok(m.shade), m.shading, ok(m.bumps), m.bumpy, m.set)
end

"`look` for only the triangles `kept` of its model"
chosen(l::Look, kept::Vector{Int}) = begin
  corners(list) = isempty(list) ? list : [list[3t+k] for t in kept for k in -2:0]
  Look(corners(l.normals), corners(l.places), corners(l.tints), l.made_of[kept], l.materials, l.textures)
end

"""
The triangles of a model. They're moved and scaled so that the model fits in a
ball of radius 1 round the origin, whatever size it has in its file.
"""
struct Mesh
  corners::Vector{Vec}        # three for each triangle
  normals::Vector{Vec}        # one for each triangle: the way its face points
  size::Vec                   # how wide, deep and tall the model is, in the units of its file
  look::Union{Nothing,Look}   # what the surface is made of, or nothing for a file that doesn't say. Then it's all the viewer's one colour.
end

Mesh(corners, normals, size) = Mesh(corners, normals, size, nothing)

"""
The triangles among `points` that have an area, the way each one faces, and
which triangles of `points` they are. A triangle with no area doesn't show.
"""
faces(points::Vector{Vec}) = begin
  corners, normals, kept = sizehint!(Vec[], length(points)), sizehint!(Vec[], length(points) ÷ 3), Int[]
  for i in 1:3:length(points)-2
    a, b, c = points[i], points[i+1], points[i+2]
    n = cross(b .- a, c .- a)
    len = sqrt(dot(n, n))
    len > 0 || continue
    push!(corners, a, b, c)
    push!(normals, n ./ len)
    push!(kept, (i + 2) ÷ 3)
  end
  corners, normals, kept
end

"`points`, moved and scaled to fit in a ball of radius 1 round the origin, and how wide, deep and tall they were"
fitted(points::Vector{Vec}) = begin
  length(points) >= 3 || error("The file has no triangles")
  lo = reduce((a, b) -> min.(a, b), points)
  hi = reduce((a, b) -> max.(a, b), points)
  middle = (lo .+ hi) ./ 2
  reach = sqrt(maximum(p -> dot(p .- middle, p .- middle), points))
  reach > 0 && isfinite(reach) || error("The model has no size")
  map!(p -> (p .- middle) ./ reach, points, points), hi .- lo
end

Mesh(points::Vector{Vec}) = begin
  fit, size = fitted(points)
  corners, normals = faces(fit)
  Mesh(corners, normals, size)
end

Mesh(g::GLTF.Model) = begin
  fit, size = fitted(g.points)
  corners, normals, kept = faces(fit)
  textures = Texture.(g.pictures)
  look = Look(g.normals, g.places, g.tints, g.made_of, [readable(m, textures) for m in g.materials], textures)
  Mesh(corners, normals, size, length(kept) == length(g.made_of) ? look : chosen(look, kept))
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
    corners, normals, kept = snapped(m, cells)
    (length(normals) <= most || cells <= 16) && return Mesh(corners, normals, m.size, m.look === nothing ? nothing : chosen(m.look, kept))
    # A grid with half as many points in a length leaves about a quarter of the triangles
    cells = max(16f0, floor(cells * sqrt(0.85f0 * most / length(normals))))
  end
end

"The triangles of `m` that still have three different corners when each corner moves to a grid with `cells` points in a length of 1, and which of `m`'s triangles they are"
snapped(m::Mesh, cells::Float32) = begin
  corners, normals, kept = Vec[], Vec[], Int[]
  snap(p) = round.(p .* cells) ./ cells
  for t in eachindex(m.normals)
    a, b, c = snap(m.corners[3t-2]), snap(m.corners[3t-1]), snap(m.corners[3t])
    (a == b || b == c || a == c) && continue
    push!(corners, a, b, c)
    push!(normals, m.normals[t])
    push!(kept, t)
  end
  corners, normals, kept
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

"The model in the glTF file at `path`, which ends in .glb or .gltf, or a sentence that says why there isn't one"
read_gltf(path) = begin
  isfile(path) || return "There's no file at $path"
  try
    Mesh(GLTF.model(path))
  catch e
    e isa GLTF.Unreadable ? e.why : "$(basename(path)) isn't a glTF file that can be read"
  end
end

"The model in the file at `path`: a 3MF file if its name ends in .3mf, a glTF file if it ends in .glb or .gltf, and an STL file if not"
read_model(path) = begin
  ext = lowercase(splitext(path)[2])
  ext == ".3mf" ? read_3mf(path) : ext in (".glb", ".gltf") ? read_gltf(path) : read_stl(path)
end

# --- the picture ---------------------------------------------------------------
#
# The model is drawn a triangle at a time into a grid of pixels. A second grid
# holds how near the eye each pixel's surface is, so a triangle only shows
# where nothing nearer has been drawn. Skia then draws the grid as an image.

const EYE = 4f0                                      # how far the eye is from the middle of the model, whose ball has radius 1
const FIT = 0.48                                     # the ball round the model is this much of the view's short side wide, from its middle, at a zoom of 1
const KEY_LIGHT = unit((-0.45f0, 0.6f0, 0.66f0))     # from above the eye, to its left
const FILL_LIGHT = unit((0.7f0, -0.25f0, 0.4f0))     # a weaker one from the right, so the shaded side isn't flat

"The last picture of a model, kept so that a frame in which nothing changed draws it again"
mutable struct Picture
  image::Ptr{Skia.sk_image_t}
  of::Any                    # what it's a picture of: the model, how it's turned, its colour and the picture's size
  pixels::Vector{UInt32}     # 0xAARRGGBB each, a row at a time from the top
  depth::Vector{Float32}     # 1 ÷ the distance from the eye to the surface at each pixel, or 0 where there's none
  which::Vector{Int32}       # for a model with materials: the triangle that shows at each pixel, or 0 where there's none
  Picture() = finalizer(release!, new(C_NULL, nothing, UInt32[], Float32[], Int32[]))
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

# --- the picture of a model with materials -------------------------------------
#
# This picture is made in two steps. The first finds which triangle shows at
# each pixel. The second works out the light at each pixel that has one. So a
# pixel's light is worked out once, however many triangles are behind it.
#
# The model stands in a studio. A big lamp is above the eye, to its left. The
# ceiling is bright and the floor is dark. A surface shows its own colour in
# the light that falls on it, and it reflects the studio: a rough one dimly and
# spread out, a smooth one sharply. A metal has no colour of its own to show.
# All that you see of it is the studio, reflected in its colour.
#
# Behind the model is the studio's grey wall. On a white page a white part
# wouldn't show, and on a dark page a dark part wouldn't.

"Find the triangle of `mesh` that shows at each pixel. It's as `render!`, but `which` gets the triangle's number where `render!` gives a colour, and a triangle reaches half a pixel past its edges."
function see!(which::Vector{Int32}, depth::Vector{Float32}, w::Int, h::Int, mesh::Mesh,
              (right, up, near)::NTuple{3,Vec}, focal::Float32, cx::Float32, cy::Float32)
  fill!(which, Int32(0))
  fill!(depth, 0f0)
  corners = mesh.corners
  @inbounds for t in eachindex(mesh.normals)
    a, b, c = corners[3t-2], corners[3t-1], corners[3t]
    ia, ib, ic = 1 / (EYE - dot(near, a)), 1 / (EYE - dot(near, b)), 1 / (EYE - dot(near, c))
    ax, ay = cx + focal * dot(right, a) * ia, cy - focal * dot(up, a) * ia
    bx, by = cx + focal * dot(right, b) * ib, cy - focal * dot(up, b) * ib
    qx, qy = cx + focal * dot(right, c) * ic, cy - focal * dot(up, c) * ic
    # A pixel shows the triangle if its middle is in it, or within half a pixel of it. So a part that's
    # thinner than a pixel, like a wire, is a whole line and not a row of dashes.
    x0, x1 = max(0, ceil(Int, min(ax, bx, qx) - 1)), min(w - 1, floor(Int, max(ax, bx, qx)))
    y0, y1 = max(0, ceil(Int, min(ay, by, qy) - 1)), min(h - 1, floor(Int, max(ay, by, qy)))
    (x0 > x1 || y0 > y1) && continue
    area = (bx - ax) * (qy - ay) - (qx - ax) * (by - ay)
    area == 0 && continue
    k = 1 / area
    ua, va = (by - qy) * k, (qx - bx) * k
    ub, vb = (qy - ay) * k, (ax - qx) * k
    # How much each weight changes in half a pixel, straight across its edge
    ea, eb, ec = sqrt(ua^2 + va^2) / 2, sqrt(ub^2 + vb^2) / 2, sqrt((ua + ub)^2 + (va + vb)^2) / 2
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
        if pa >= -ea && pb >= -eb && pa + pb <= 1 + ec && pd > depth[i]
          depth[i] = pd
          which[i] = t % Int32
        end
        pa += ua; pb += ub; pd += ud
      end
      wa += va; wb += vb; d += vd
    end
  end
  which
end

# A picture's colours are a screen's numbers, which aren't amounts of light. Light is added up as amounts.
const LIGHT = Float32[(x = i / 255; x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055)^2.4) for i in 0:255]
const STEPS = 4095
const SCREEN = UInt32[round(UInt32, 255 * (x = i / STEPS; x <= 0.0031308 ? 12.92x : 1.055x^(1 / 2.4) - 0.055)) for i in 0:STEPS]

"A screen's number for an amount of light. Light that's too bright for the screen gets a little less bright, so that it keeps its colour."
shown(x::Float32) = begin
  x = x <= 0.75f0 ? max(x, 0f0) : 1 - 0.25f0 * exp(4 * (0.75f0 - x))
  @inbounds SCREEN[round(Int, x * STEPS)+1]
end

"0xAARRGGBB for the amounts of red, green and blue light `c`"
shown(c::Vec) = 0xff000000 | shown(c[1]) << 16 | shown(c[2]) << 8 | shown(c[3])

"Pixel `i` of a row or a column of `n`, when the picture's edge is `how`: 0 the picture again, 1 its edge goes on, 2 the picture in a mirror"
@inline wrapped(i::Int, n::Int, how::Int) =
  how == 1 ? clamp(i, 0, n - 1) : how == 2 ? (j = mod(i, 2n); j < n ? j : 2n - 1 - j) : mod(i, n)

const BLANK = (255f0, 255f0, 255f0, 255f0)

"""
The picture's red, green, blue and alpha at the place `(u, v)`, each from 0 to
255. `spread` is log2 of how many pixels of the picture, at its full size, go
across one pixel of the view. The size of picture that's read is the one whose
pixels are nearest to the view's.
"""
@inline function sample(t::Texture, paint::GLTF.Paint, u::Float32, v::Float32, spread::Float32)
  (abs(u) < 1f6 && abs(v) < 1f6) || return BLANK   # a place that isn't a number, or is one no picture reaches
  @inbounds begin
    l = t.levels[clamp(round(Int, spread + t.bits), 0, length(t.levels) - 1)+1]
    # The four pixels round the place, each weighed by how near it is
    x, y = u * l.w - 0.5f0, v * l.h - 0.5f0
    x0, y0 = floor(Int, x), floor(Int, y)
    fx, fy = x - x0, y - y0
    xa, xb = wrapped(x0, l.w, paint.across), wrapped(x0 + 1, l.w, paint.across)
    ya, yb = wrapped(y0, l.h, paint.down) * l.w + 1, wrapped(y0 + 1, l.h, paint.down) * l.w + 1
    p, q, r, s = l.pixels[ya+xa], l.pixels[ya+xb], l.pixels[yb+xa], l.pixels[yb+xb]
    wp, wq, wr, ws = (1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy
    channel(n) = wp * (p >> n & 0xff) + wq * (q >> n & 0xff) + wr * (r >> n & 0xff) + ws * (s >> n & 0xff)
    (channel(0), channel(8), channel(16), channel(24))
  end
end

"The amounts of light that a picture's colour stands for"
@inline light(c::NTuple{4,Float32}) = @inbounds (LIGHT[round(Int, c[1])+1], LIGHT[round(Int, c[2])+1], LIGHT[round(Int, c[3])+1])

# The studio's light, as amounts. 1 is as bright as the screen gets.
const LAMP, FILL = 0.7f0, 0.2f0            # on a surface that faces the big lamp, and one that faces the weaker lamp
const CEILING, FLOOR = 0.36f0, 0.2f0       # on a surface that faces up and one that faces down, from all of the room
const WALL, TOP, GROUND = 0.55f0, 1.0f0, 0.3f0   # how bright the room looks in a mirror: at eye level, overhead and below
const BACK_TOP, BACK_BOTTOM = 0.15f0, 0.3f0      # how bright the wall behind the model is, at the top of the view and at the bottom
const GLARE, LAMP_SIZE = 3.2f0, 0.03f0     # how bright the big lamp looks in a mirror, and how big

"""
How bright the studio looks in a surface that's `rough`. `height` is how far up
the reflected ray points, from -1 to 1. `lamp` is how near it points to the big
lamp: 1 is straight at it. A rough surface sees a wide patch of the room at
once, so the line between wall and floor blurs and the lamp spreads and dims.
"""
@inline studio(height::Float32, lamp::Float32, rough::Float32) = begin
  blur = 0.05f0 + 0.9f0 * rough
  t = clamp(height / blur, -1f0, 1f0)
  up = 0.5f0 + t * (0.75f0 - 0.25f0 * t * t)   # 0 below the line, 1 above it, with a smooth step between
  room = GROUND + (WALL + (TOP - WALL) * max(height, 0f0) - GROUND) * up
  size = LAMP_SIZE + 0.5f0 * rough * rough
  room + GLARE * (LAMP_SIZE / size) * exp((lamp - 1) / size)
end

"""
How much of what it reflects a surface sends to the eye: a share of its own
reflecting colour, and a share that every surface adds at a shallow angle.
`facing` is 1 when the eye looks straight at the surface and 0 when it looks
along it. It's a fit to measured surfaces that games use.
"""
@inline reflected(rough::Float32, facing::Float32) = begin
  r1, r2, r3, r4 = 1 - rough, 0.0425f0 - 0.0275f0 * rough, 1.04f0 - 0.572f0 * rough, 0.022f0 * rough - 0.04f0
  a = min(r1 * r1, exp2(-9.28f0 * facing)) * r1 + r2
  (-1.04f0 * a + r3, 1.04f0 * a + r4)
end

"The way a corner faces, turned to the side `flat` that its triangle shows. A corner that the file says nothing of faces as the triangle does."
@inline side(n::Vec, flat::Vec) = n == (0f0, 0f0, 0f0) ? flat : dot(n, flat) < 0 ? .-n : n

"`n` with a length of 1, or `other` if it has no length"
@inline unit(n::Vec, other::Vec) = (len = dot(n, n); len > 1f-12 ? n ./ sqrt(len) : other)

"""
Work out the light at each pixel in `rows` that `see!` found a triangle for.
The other pixels show the wall behind the model. The picture is `h` pixels tall.
"""
function shade!(pixels::Vector{UInt32}, which::Vector{Int32}, w::Int, h::Int, rows::UnitRange{Int}, mesh::Mesh, look::Look,
                (right, up, near)::NTuple{3,Vec}, focal::Float32, cx::Float32, cy::Float32)
  corners = mesh.corners
  eye = near .* EYE
  towards(l) = right .* l[1] .+ up .* l[2] .+ near .* l[3]
  lamp, weak = towards(KEY_LIGHT), towards(FILL_LIGHT)
  curved, placed, tinted = !isempty(look.normals), !isempty(look.places), !isempty(look.tints)
  none = (0f0, 0f0, 0f0)
  # What's known of the last pixel's triangle. The next pixel most often shows the same one.
  before = Int32(0)
  a = b = c = na = nb = nc = flat = ta = tb = tc = along = down = none
  ua = ub = uc = (0f0, 0f0)
  ia = ib = ic = ax = ay = bx = by = qx = qy = k = spread = 0f0
  m = look.materials[1]
  @inbounds for row in rows, col in 0:w-1
    i = row * w + col + 1
    t = which[i]
    if t == 0
      wall = BACK_TOP + (BACK_BOTTOM - BACK_TOP) * (row + 0.5f0) / h
      pixels[i] = shown((wall, wall, wall))
      continue
    end
    if t != before
      before = t
      a, b, c = corners[3t-2], corners[3t-1], corners[3t]
      ia, ib, ic = 1 / (EYE - dot(near, a)), 1 / (EYE - dot(near, b)), 1 / (EYE - dot(near, c))
      ax, ay = cx + focal * dot(right, a) * ia, cy - focal * dot(up, a) * ia
      bx, by = cx + focal * dot(right, b) * ib, cy - focal * dot(up, b) * ib
      qx, qy = cx + focal * dot(right, c) * ic, cy - focal * dot(up, c) * ic
      area = (bx - ax) * (qy - ay) - (qx - ax) * (by - ay)
      k = 1 / area
      # A face is lit on the side that the eye sees, whichever way the file says it points
      flat = mesh.normals[t]
      dot(flat, near) * EYE - dot(flat, a) < 0 && (flat = .-flat)
      na = nb = nc = flat
      curved && ((na, nb, nc) = (side(look.normals[3t-2], flat), side(look.normals[3t-1], flat), side(look.normals[3t], flat)))
      m = look.materials[look.made_of[t]]
      tinted && ((ta, tb, tc) = (look.tints[3t-2], look.tints[3t-1], look.tints[3t]))
      along = none
      if placed
        ua, ub, uc = look.places[3t-2], look.places[3t-1], look.places[3t]
        du1, dv1, du2, dv2 = ub[1] - ua[1], ub[2] - ua[2], uc[1] - ua[1], uc[2] - ua[2]
        det = du1 * dv2 - du2 * dv1
        # How much of a picture the triangle holds, against how many pixels of the view it covers
        spread = det != 0 ? log2(abs(det) / abs(area)) / 2 : -100f0
        if m.bumps.image != 0 && det != 0
          # The ways across and down the picture, as they lie on the triangle
          e1, e2 = b .- a, c .- a
          along, down = (e1 .* dv2 .- e2 .* dv1) ./ det, (e2 .* du1 .- e1 .* du2) ./ det
        end
      end
    end
    # How much of each corner the pixel has. A far corner covers less of the view, so its share is scaled up.
    x, y = col + 0.5f0, row + 0.5f0
    wa = ((bx - x) * (qy - y) - (qx - x) * (by - y)) * k
    wb = ((qx - x) * (ay - y) - (ax - x) * (qy - y)) * k
    pa, pb, pc = wa * ia, wb * ib, (1 - wa - wb) * ic
    s = 1 / (pa + pb + pc)
    la, lb, lc = pa * s, pb * s, pc * s
    at = a .* la .+ b .* lb .+ c .* lc
    n = unit(na .* la .+ nb .* lb .+ nc .* lc, flat)
    colour, metal, rough, glow, shade = m.colour, m.metal, m.rough, m.glow, 1f0
    tinted && (colour = colour .* (ta .* la .+ tb .* lb .+ tc .* lc))
    if placed
      u, v = ua[1] * la + ub[1] * lb + uc[1] * lc, ua[2] * la + ub[2] * lb + uc[2] * lc
      m.base.image != 0 && (colour = colour .* light(sample(look.textures[m.base.image], m.base, u, v, spread)))
      if m.surface.image != 0
        p = sample(look.textures[m.surface.image], m.surface, u, v, spread)
        rough, metal = rough * p[2] / 255, metal * p[3] / 255
      end
      m.shade.image != 0 && (shade = 1 + m.shading * (sample(look.textures[m.shade.image], m.shade, u, v, spread)[1] / 255 - 1))
      m.glowing.image != 0 && (glow = glow .* light(sample(look.textures[m.glowing.image], m.glowing, u, v, spread)))
      if along != none
        # The picture says which way the point faces, measured along the picture, down it and out of the surface
        p = sample(look.textures[m.bumps.image], m.bumps, u, v, spread)
        across = unit(along .- n .* dot(n, along), none)
        if across != none
          # A picture's green is how far the point leans up the picture, and `down` is the way down it
          over = cross(n, across)
          dot(over, down) > 0 && (over = .-over)
          tx, ty, tz = (p[1] / 127.5f0 - 1) * m.bumpy, (p[2] / 127.5f0 - 1) * m.bumpy, p[3] / 127.5f0 - 1
          n = unit(across .* tx .+ over .* ty .+ n .* tz, n)
        end
      end
    end
    rough, metal = clamp(rough, 0.04f0, 1f0), clamp(metal, 0f0, 1f0)
    to_eye = unit(eye .- at, near)
    facing = max(dot(n, to_eye), 1f-3)
    ray = n .* 2facing .- to_eye   # the way that light comes from to reach the eye off the surface
    fallen = shade * (FLOOR + (CEILING - FLOOR) * (0.5f0 + 0.5f0 * dot(up, n))) + LAMP * max(0f0, dot(n, lamp)) + FILL * max(0f0, dot(n, weak))
    seen = shade * studio(dot(up, ray), dot(lamp, ray), rough)
    own, extra = reflected(rough, facing)
    mirror = colour .* metal .+ 0.04f0 * (1 - metal)   # the colour that the surface reflects in
    pixels[i] = shown(colour .* ((1 - metal) * fallen) .+ (mirror .* own .+ extra) .* seen .+ glow)
  end
  pixels
end

"Draw `mesh`, which has materials, as `render!` draws one that has none"
render!(p::Picture, w::Int, h::Int, mesh::Mesh, look::Look, sight, focal::Float32, cx::Float32, cy::Float32) = begin
  length(p.which) == w * h || (p.which = Vector{Int32}(undef, w * h))
  see!(p.which, p.depth, w, h, mesh, sight, focal, cx, cy)
  shade!(p.pixels, p.which, w, h, 0:h-1, mesh, look, sight, focal, cx, cy)
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

const SMALLEST, BIGGEST = 0.4, 60.0

@def mutable struct STLViewer <: SemanticUI
  path::String = ""
  turn::Float64 = 35.0                # degrees round the model's upright axis
  tilt::Float64 = 22.0                # degrees the eye is above the model. At 90 it looks straight down.
  zoom::Float64 = 1.0                 # 1 fits the whole model in the view however it's turned
  shift::NTuple{2,Float64} = (0.0, 0.0)   # how many px right of the view's middle, and below it, the middle of the model shows
  height::px = 340px                  # of the view. The viewer is as wide as it's given room for.
  color::Colorant = colorant"rgb(132,160,196)"
  fill::Bool = false                  # it takes all the room that it's given and has no frame, for when it's all that a window shows
  # What it remembers between frames
  model::Any = nothing                # the Mesh of the file, or a sentence that says why there isn't one
  rough::Any = nothing                # a Mesh with fewer triangles to draw while a big model turns, or nothing for a small one
  moved::Float64 = 0.0                # when it was last turned or made bigger or smaller
  home::Any = nothing                 # the turn, tilt and zoom it was made with, which two clicks put back
  read::Float64 = -1.0                # when the file had last changed, the last time it was read
  grab::Any = nothing                 # where the mouse was on the last move of a drag
  pivot::Vec = (0f0, 0f0, 0f0)        # the point of the model that a drag turns it round
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

const SETTLE = 0.2   # seconds after a model last moved until it's drawn in full

"Did the model move a moment ago?"
moving(v::STLViewer) = time() - v.moved < SETTLE
"Is a big model still moving? Its rougher copy is drawn while it is."
turning(v::STLViewer) = v.rough !== nothing && moving(v)
"Is a model with materials still moving? It's drawn with fewer pixels while it is, since each pixel takes more work."
sketched(v::STLViewer) = v.model isa Mesh && v.model.look !== nothing && moving(v)

# The most pixels that a model with materials is drawn with: when it's still, and while it moves
const FINE, QUICK = 6_000_000, 900_000
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
  v.home === nothing && (v.home = (v.turn, v.tilt, v.zoom, v.shift))
  # A model that has just stopped needs one more frame, to draw it in full
  (turning(v) || sketched(v)) && redraw_in!(v, SETTLE / 2)
  grow = GrowType.Grow
  # One that fills its room has no line round it and no round corners, since the window's edges are its edges
  frame = v.fill ? (height(grow=grow),) : (radius(8px), border(1px, :solid, t.line))
  Column(width(grow=grow), frame..., background(t.surface), clip=true,
    Box(width(grow=grow), v.fill ? height(grow=grow) : height(v.height), padding(16px),
      (model isa Mesh ? () : (Text(String(model), size=sized(12pt, t), color=t.dim),))...),
    Row(width(grow=grow), padding(12px, 7px), child_gap=12px, background(t.hover), (v.fill ? () : (radius(0px, 7px),))...,
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
  look = mesh.look
  look === nothing || (detail = min(detail, sqrt((sketched(v) ? QUICK : FINE) / max(1, area.width.value * area.height.value))))
  w, h = round(Int, area.width.value * detail), round(Int, area.height.value * detail)
  (w < 1 || h < 1) && return
  p = v.picture
  # A model with materials has its own colours
  colour = look === nothing ? convert(RGB{Float32}, v.color) : RGB{Float32}(0, 0, 0)
  of = (mesh, v.turn, v.tilt, v.zoom, v.shift, colour, w, h)
  if p.of != of
    length(p.pixels) == w * h || (p.pixels = Vector{UInt32}(undef, w * h); p.depth = Vector{Float32}(undef, w * h))
      focal = Float32(FIT * min(w, h) * v.zoom) * sqrt(EYE^2 - 1)
    cx, cy = Float32(w / 2 + v.shift[1] * detail), Float32(h / 2 + v.shift[2] * detail)
    if look === nothing
      render!(p.pixels, p.depth, w, h, mesh, sight(v.turn, v.tilt), focal, cx, cy, (colour.r, colour.g, colour.b))
    else
      render!(p, w, h, mesh, look, sight(v.turn, v.tilt), focal, cx, cy)
    end
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
  inset, corner = v.fill ? (0px, 0px) : (1px, 7px)
  edge = Ref(Skia.sk_rect_t(flt(ui.left + inset), flt(ui.top + inset), flt(ui.left + ui.width - inset), flt(ui.top + ui.height - inset)))
  clip = Skia.sk_path_new()
  Skia.sk_path_add_rounded_rect(clip, edge, flt(corner), flt(corner), Skia.SK_PATH_DIRECTION_CW)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_canvas_save(ctx)
  Skia.sk_canvas_clip_path_with_operation(ctx, clip, Skia.SK_CLIP_OP_INTERSECT, true)
  Skia.sk_canvas_draw_image_rect(ctx, p.image, from, to, Ref(smooth), paint, Skia.SRC_RECT_CONSTRAINT_FAST)
  Skia.sk_canvas_restore(ctx)
  Skia.sk_paint_delete(paint)
  Skia.sk_path_delete(clip)
end

# --- where a point of the model shows ------------------------------------------
#
# The model's middle shows `shift` px from the middle of the view. When the
# model grows, the shift changes so that the part under the mouse stays there.
# When it turns, the shift changes so that the part it turns round stays where
# it is.

"The part of the viewer that shows the model, or nothing before the viewer is first drawn"
stage(v::STLViewer) = (r = rect(v); r === nothing || isempty(r.children) ? nothing : r.children[1])

"How many px from the middle of the view the point `at` of a window is: right of it, and below it"
from_middle(area, at) = ((at[1] - area.left - area.width / 2).value, (at[2] - area.top - area.height / 2).value)

"How many px wide a length of 1 shows in the view `area`, for a point that's 1 away from the eye"
focal(v::STLViewer, area) = FIT * min(area.width.value, area.height.value) * v.zoom * sqrt(EYE^2 - 1)

"How many px from the middle of the view the point `p` of the model shows"
place(v::STLViewer, area, p::Vec) = begin
  right, up, near = sight(v.turn, v.tilt)
  k = focal(v, area) / (EYE - dot(near, p))
  (v.shift[1] + k * dot(right, p), v.shift[2] - k * dot(up, p))
end

"""
The point of the model that shows `at` px from the middle of the view. It's on
the model's surface if the last picture has a surface there. If not, it's as
far from the eye as the middle of the model.
"""
point(v::STLViewer, area, at) = begin
  right, up, near = sight(v.turn, v.tilt)
  p, far = v.picture, Float64(EYE)
  if p.of isa Tuple && p.of[2:5] == (v.turn, v.tilt, v.zoom, v.shift)
    w, h = p.of[end-1], p.of[end]
    col, row = floor(Int, (at[1] / area.width.value + 0.5) * w), floor(Int, (at[2] / area.height.value + 0.5) * h)
    (0 <= col < w && 0 <= row < h && p.depth[row*w+col+1] > 0) && (far = 1 / p.depth[row*w+col+1])
  end
  k = far / focal(v, area)
  Vec(right .* ((at[1] - v.shift[1]) * k) .+ up .* ((v.shift[2] - at[2]) * k) .+ near .* (EYE - far))
end

"Turn the model by `turn` degrees and tilt it by `tilt`, round the point `pivot`, which stays where it shows"
turn!(v::STLViewer, turn, tilt, pivot::Vec) = begin
  area = stage(v)
  was = area === nothing ? nothing : place(v, area, pivot)
  v.turn = mod(v.turn + turn, 360)
  v.tilt = clamp(v.tilt + tilt, -90, 90)
  was === nothing || (v.shift = v.shift .+ was .- place(v, area, pivot))
  moved!(v)
end

"Turn the model round the part that shows in the middle of the view, as the arrow keys do"
turn!(v::STLViewer, turn, tilt) = (area = stage(v); turn!(v, turn, tilt, area === nothing ? v.pivot : point(v, area, (0.0, 0.0))))

"""
Make the model `by` times bigger. `at` is where the mouse is in the window. The
part of the model under it stays under it as the model grows. As the model gets
smaller again, its middle goes back to the middle of the view.
"""
zoom!(v::STLViewer, by, at) = begin
  new = clamp(v.zoom * by, SMALLEST, BIGGEST)
  area = stage(v)
  if new > v.zoom && area !== nothing
    m = from_middle(area, at)
    v.shift = m .- (m .- v.shift) .* (new / v.zoom)
  elseif new < v.zoom
    v.shift = v.shift .* (v.zoom > 1 ? max(0.0, (new - 1) / (v.zoom - 1)) : 0.0)
  end
  v.zoom = new
  moved!(v)
end

# --- the mouse -----------------------------------------------------------------

cursor(::STLViewer) = :hand

"Show the model as it was at first"
reset!(v::STLViewer) = ((v.turn, v.tilt, v.zoom, v.shift) = v.home; moved!(v))

onkey(v::STLViewer, e::KeyPress{Keys.mouse_left}) = begin
  focus(v)
  now = time()
  now - v.clicked < 0.4 && v.home !== nothing && reset!(v)
  v.clicked = now
  v.grab = e.window.mouse
  # A drag from here turns the model round the part that was pressed
  area = stage(v)
  area === nothing || (v.pivot = point(v, area, from_middle(area, e.window.mouse)))
  handled
end

# A drag turns the model: half a degree for each px. Up and down tilt it, as far as the top and the underside.
onmouse(v::STLViewer, e::MouseMove) = begin
  (Keys.mouse_left in e.window.keys && v.grab !== nothing) || (v.grab = nothing; return)
  dx, dy = (e.position[1] - v.grab[1]).value, (e.position[2] - v.grab[2]).value
  v.grab = e.position
  # A click that moved isn't half of a double click
  (dx == 0 && dy == 0) || (v.clicked = 0.0; turn!(v, dx / 2, dy / 2, v.pivot))
  handled   # the drag is the viewer's, so the nodes above don't act on it too
end

# Scrolling with ⌘ held makes the model bigger or smaller. Without ⌘ it scrolls the page that the viewer is on.
# A viewer that fills its room is on no page, so any scroll makes its model bigger or smaller.
onscroll(v::STLViewer, e::MouseScroll) = begin
  (v.fill || Keys.cmd in e.window.keys) || return
  zoom!(v, exp(e.delta[2].value / 10), e.window.mouse)
  handled
end

# A pinch on the trackpad makes the model bigger or smaller too
onpinch(v::STLViewer, e::Pinch) = (zoom!(v, e.scale, e.window.mouse); handled)

# The arrow keys turn it too, once a click has given it the keyboard
onkey(v::STLViewer, ::KeyPress{Keys.left}) = (turn!(v, -10, 0); handled)
onkey(v::STLViewer, ::KeyPress{Keys.right}) = (turn!(v, 10, 0); handled)
onkey(v::STLViewer, ::KeyPress{Keys.up}) = (turn!(v, 0, 10); handled)
onkey(v::STLViewer, ::KeyPress{Keys.down}) = (turn!(v, 0, -10); handled)

export STLViewer, Mesh, read_stl, read_3mf, read_gltf, read_model
