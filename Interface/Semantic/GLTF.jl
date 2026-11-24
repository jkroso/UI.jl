# Reads a glTF model, the kind of file that 3D programs and web pages give each
# other. Unlike an STL file it says how the surface looks: its colour, how much
# it's a metal, how rough it is, and the pictures that are wrapped round it.
#
#     model("satellite.glb")    # a Model: triangles, and what each one is made of
#     model(bytes)              # the same, from the bytes of a .glb file that code made
#
# The file comes in two forms. A .glb file is one file: a text in JSON, then the
# bytes that the text describes. A .gltf file is only the text, and it names
# other files for the bytes and the pictures, or holds them in base64.
#
# The text is a tree of nodes. A node can have a mesh, and it moves, turns and
# scales all that's under it. A mesh has parts, each with one material. A part's
# numbers come from "accessors", which say where in the bytes they are.
#
# A file can also say what's round the model. A node can be a light that shines
# one way, like the Sun (the format's KHR_lights_punctual). And a scene can name
# a picture of the whole sky, which is this reader's own addition:
#
#     "scenes": [{"nodes": [0], "extras": {"sky": {"image": 3}}}]
#
# The picture is twice as wide as it's tall. Its top row is straight up (y), its
# bottom row straight down, and its middle column is the way that -z points.
# Going right in the picture turns towards x.
#
# JSON is read here, with no library, so that an app needs nothing more to read
# a model.

const Vec = NTuple{3,Float32}
const UV = NTuple{2,Float32}

# --- JSON ----------------------------------------------------------------------
#
# Each reader takes the text's bytes and where to start. It gives the value and
# where the text goes on after it.

past_space(b, i) = (while b[i] in (0x20, 0x09, 0x0a, 0x0d); i += 1 end; i)

value(b, i) = begin
  i = past_space(b, i)
  c = b[i]
  c == UInt8('{') ? object(b, i + 1) :
  c == UInt8('[') ? list(b, i + 1) :
  c == UInt8('"') ? words(b, i + 1) :
  c == UInt8('t') ? (true, i + 4) :
  c == UInt8('f') ? (false, i + 5) :
  c == UInt8('n') ? (nothing, i + 4) : number(b, i)
end

object(b, i) = begin
  out = Dict{String,Any}()
  i = past_space(b, i)
  b[i] == UInt8('}') && return out, i + 1
  while true
    i = past_space(b, i)
    b[i] == UInt8('"') || error("not JSON")
    key, i = words(b, i + 1)
    i = past_space(b, i)
    b[i] == UInt8(':') || error("not JSON")
    out[key], i = value(b, i + 1)
    i = past_space(b, i)
    b[i] == UInt8('}') && return out, i + 1
    b[i] == UInt8(',') || error("not JSON")
    i += 1
  end
end

list(b, i) = begin
  out = Any[]
  i = past_space(b, i)
  b[i] == UInt8(']') && return out, i + 1
  while true
    x, i = value(b, i)
    push!(out, x)
    i = past_space(b, i)
    b[i] == UInt8(']') && return out, i + 1
    b[i] == UInt8(',') || error("not JSON")
    i += 1
  end
end

number(b, i) = begin
  j = i
  while j <= length(b) && (UInt8('0') <= b[j] <= UInt8('9') || b[j] in (UInt8('-'), UInt8('+'), UInt8('.'), UInt8('e'), UInt8('E'))); j += 1 end
  parse(Float64, String(b[i:j-1])), j
end

const ESCAPES = Dict(UInt8('n') => '\n', UInt8('t') => '\t', UInt8('r') => '\r', UInt8('b') => '\b', UInt8('f') => '\f')

"The text that goes on from byte `i` to the next quote mark"
words(b, i) = begin
  j = i
  while b[j] != UInt8('"') && b[j] != UInt8('\\'); j += 1 end
  b[j] == UInt8('"') && return String(b[i:j-1]), j + 1
  # A backslash starts a character that's written another way
  io = IOBuffer()
  write(io, view(b, i:j-1))
  while b[j] != UInt8('"')
    if b[j] != UInt8('\\')
      write(io, b[j])
      j += 1
    elseif b[j+1] == UInt8('u')
      n = parse(UInt32, String(b[j+2:j+5]), base=16)
      j += 6
      # A character past 0xffff is written as two halves
      if 0xd800 <= n <= 0xdbff && b[j] == UInt8('\\') && b[j+1] == UInt8('u')
        n = 0x10000 + ((n - 0xd800) << 10) + (parse(UInt32, String(b[j+2:j+5]), base=16) - 0xdc00)
        j += 6
      end
      print(io, Char(n))
    else
      print(io, get(ESCAPES, b[j+1], Char(b[j+1])))
      j += 2
    end
  end
  String(take!(io)), j + 1
end

"The value that the JSON text `bytes` holds: a Dict, a Vector, a String, a Float64, a Bool or nothing"
json(bytes::Vector{UInt8}) = value(bytes, 1)[1]

const NONE = Dict{String,Any}()
"The Dict under `key`, or an empty one"
under(d, key) = (x = get(d, key, nothing); x isa Dict ? x : NONE)

# --- the file ------------------------------------------------------------------

"A model that this reader can't read, with a sentence that says why"
struct Unreadable <: Exception
  why::String
end

"A glTF file that's open: its text, the bytes that came with the text, and the folder that its other files are in"
struct File
  json::Dict{String,Any}
  bytes::Vector{UInt8}
  folder::String
  read::Dict{String,Vector{UInt8}}   # the other files that have been read, by the name the text gives them
end

u32(b, i) = UInt32(b[i+1]) | UInt32(b[i+2]) << 8 | UInt32(b[i+3]) << 16 | UInt32(b[i+4]) << 24

const PACKINGS = Dict("KHR_draco_mesh_compression" => "Draco", "EXT_meshopt_compression" => "Meshopt")

File(path::AbstractString) = File(read(path), dirname(abspath(path)), basename(path))

"The file that `bytes` holds, as a .glb file has them. `folder` is where its other files are, and `name` is what a sentence calls it."
File(bytes::Vector{UInt8}, folder::AbstractString="", name::AbstractString="The model") = begin
  text, rest = bytes, UInt8[]
  if length(bytes) >= 12 && u32(bytes, 0) == 0x46546c67   # "glTF"
    # A .glb file is a row of chunks. Each says how long it is and what it is.
    at = 12
    while at + 8 <= length(bytes)
      n, kind = Int(u32(bytes, at)), u32(bytes, at + 4)
      kind == 0x4e4f534a && (text = bytes[at+9:at+8+n])   # "JSON"
      kind == 0x004e4942 && (rest = bytes[at+9:at+8+n])   # "BIN"
      at += 8 + n
    end
  end
  f = File(json(text), rest, String(folder), Dict{String,Vector{UInt8}}())
  for packing in get(f.json, "extensionsRequired", [])
    haskey(PACKINGS, packing) && throw(Unreadable("$name is packed with $(PACKINGS[packing]), which this viewer doesn't unpack"))
  end
  f
end

const BASE64 = let t = fill(0xff, 256)
  for (n, c) in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"); t[UInt8(c)+1] = n - 1 end
  t
end

"The bytes that a text in base64 stands for"
base64(text::AbstractString) = begin
  out, bits, n = UInt8[], UInt32(0), 0
  for c in codeunits(text)
    x = BASE64[c+1]
    x == 0xff && continue
    bits, n = bits << 6 | x, n + 6
    n >= 8 && (n -= 8; push!(out, (bits >> n) % UInt8))
  end
  out
end

"A name as it is on disk, from one written with %20 for a space"
plain(uri) = replace(uri, r"%[0-9a-fA-F]{2}" => s -> string(Char(parse(UInt8, s[2:3], base=16))))

"The bytes that the text names with `uri`: a file beside this one, or bytes written out in base64"
bytes_at(f::File, uri::AbstractString) = get!(f.read, uri) do
  startswith(uri, "data:") && return base64(SubString(uri, something(findfirst(',', uri), 0) + 1))
  occursin(r"^[a-z][a-z0-9+.-]*:"i, uri) && error("a file that isn't on this computer")
  read(joinpath(f.folder, plain(uri)))
end

"The bytes of buffer `n`. Numbers in the text count from 0."
buffer(f::File, n) = (uri = get(f.json["buffers"][Int(n)+1], "uri", nothing); uri === nothing ? f.bytes : bytes_at(f, uri))

# --- numbers -------------------------------------------------------------------

const KINDS = Dict(5120 => Int8, 5121 => UInt8, 5122 => Int16, 5123 => UInt16, 5125 => UInt32, 5126 => Float32)
const WIDTHS = Dict("SCALAR" => 1, "VEC2" => 2, "VEC3" => 3, "VEC4" => 4, "MAT2" => 4, "MAT3" => 9, "MAT4" => 16)

# A whole number can stand for a fraction: all of its range for 0 to 1, or for -1 to 1
fraction(x::Float32) = x
fraction(x::T) where T<:Unsigned = Float32(x / typemax(T))
fraction(x::T) where T<:Signed = max(Float32(x / typemax(T)), -1f0)

"Fill `out`, a column for each element, with numbers of type `T` that start at byte `start` and come every `stride` bytes"
fill_from!(out::Matrix{R}, bytes::Vector{UInt8}, start::Int, stride::Int, ::Type{T}, fractions::Bool) where {R,T} = begin
  wide, count = size(out)
  count == 0 && return out
  (start >= 0 && start + stride * (count - 1) + wide * sizeof(T) <= length(bytes)) || error("The file is cut short")
  GC.@preserve bytes for e in 0:count-1, k in 0:wide-1
    x = ltoh(unsafe_load(Ptr{T}(pointer(bytes, start + stride * e + k * sizeof(T) + 1))))
    @inbounds out[k+1, e+1] = fractions ? fraction(x) : R(x)
  end
  out
end

"`count` elements, each `wide` numbers of the kind `kind`, from `offset` bytes into buffer view `view`"
numbers(f::File, view, offset, kind, wide, count, fractions, ::Type{R}) where R = begin
  v = f.json["bufferViews"][Int(view)+1]
  for name in keys(under(v, "extensions"))
    haskey(PACKINGS, name) && throw(Unreadable("The model is packed with $(PACKINGS[name]), which this viewer doesn't unpack"))
  end
  T = KINDS[Int(kind)]
  stride = Int(get(v, "byteStride", 0))
  fill_from!(Matrix{R}(undef, wide, count), buffer(f, v["buffer"]), Int(get(v, "byteOffset", 0)) + Int(offset),
             stride == 0 ? wide * sizeof(T) : stride, T, fractions && R <: AbstractFloat)
end

"The numbers of accessor `n`, as a matrix with a column for each element"
numbers(f::File, n, ::Type{R}=Float32) where R = begin
  a = f.json["accessors"][Int(n)+1]
  wide, count, fractions = WIDTHS[a["type"]], Int(a["count"]), get(a, "normalized", false) === true
  out = haskey(a, "bufferView") ?
    numbers(f, a["bufferView"], get(a, "byteOffset", 0), a["componentType"], wide, count, fractions, R) : zeros(R, wide, count)
  if haskey(a, "sparse")
    # A few elements are given apart from the rest: which ones, then their numbers
    s = a["sparse"]
    few, which, values = Int(s["count"]), s["indices"], s["values"]
    at = numbers(f, which["bufferView"], get(which, "byteOffset", 0), which["componentType"], 1, few, false, Int)
    new = numbers(f, values["bufferView"], get(values, "byteOffset", 0), a["componentType"], wide, few, fractions, R)
    for (k, e) in enumerate(at); out[:, e+1] = new[:, k] end
  end
  out
end

# --- where a node puts its mesh ------------------------------------------------
#
# A 4 × 4 matrix moves, turns and scales a point. A node's matrix is its
# parent's times its own.

times(a::Matrix{Float64}, b::Matrix{Float64}) = [sum(a[i, k] * b[k, j] for k in 1:4) for i in 1:4, j in 1:4]

"The matrix of one node: written out, or as a move, a turn and a scale"
matrix(node) = begin
  haskey(node, "matrix") && return reshape(Float64.(node["matrix"]), 4, 4)
  x, y, z, w = Float64.(get(node, "rotation", [0, 0, 0, 1]))
  sx, sy, sz = Float64.(get(node, "scale", [1, 1, 1]))
  tx, ty, tz = Float64.(get(node, "translation", [0, 0, 0]))
  [(1-2(y*y+z*z))*sx  2(x*y-z*w)*sy      2(x*z+y*w)*sz      tx
   2(x*y+z*w)*sx      (1-2(x*x+z*z))*sy  2(y*z-x*w)*sz      ty
   2(x*z-y*w)*sx      2(y*z+x*w)*sy      (1-2(x*x+y*y))*sz  tz
   0                  0                  0                  1]
end

# In a glTF file y is up and the front faces z. The viewer has z up, as an STL file has, so the front faces -y.
const UPRIGHT = [1.0 0 0 0; 0 0 -1 0; 0 1 0 0; 0 0 0 1]

"""
The matrix that turns the way a surface faces as `m` moves the surface. It's
not `m` itself when `m` scales one axis more than another.
"""
facing(m::Matrix{Float64}) = begin
  a, b, c, d, e, f, g, h, i = m[1, 1], m[1, 2], m[1, 3], m[2, 1], m[2, 2], m[2, 3], m[3, 1], m[3, 2], m[3, 3]
  det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
  s = det < 0 ? -1.0 : 1.0
  s .* [e*i-f*h  f*g-d*i  d*h-e*g
        c*h-b*i  a*i-c*g  b*g-a*h
        b*f-c*e  c*d-a*f  a*e-b*d]
end

# --- what a surface is made of -------------------------------------------------

"A picture that's wrapped round the model: which of the file's pictures, counted from 1, and what's past its edges"
struct Paint
  image::Int    # 0 when there's no picture
  across::Int   # past its left and right edges: 0 the picture again, 1 its edge goes on, 2 the picture in a mirror
  down::Int     # the same for its top and bottom
end

const BARE = Paint(0, 0, 0)

"""
What a part of the model is made of. A number here is for all of the part. A
picture gives a number for each point, and the two are multiplied.
"""
struct Material
  colour::Vec       # of the surface, as amounts of light from 0 to 1, not as a screen's numbers
  metal::Float32    # 1 for a metal, which shows its colour only in what it reflects, and 0 for anything else
  rough::Float32    # 0 for a mirror, 1 for chalk
  glow::Vec         # light that the surface gives off itself
  base::Paint       # the colour
  surface::Paint    # how rough, in the picture's green, and how much a metal, in its blue
  glowing::Paint    # the light it gives off
  shade::Paint      # how much of the light from all round reaches each point, in the picture's red
  shading::Float32  # how much of that shade to use, from 0 to 1
  bumps::Paint      # which way each point faces, for dents and scratches that the triangles don't have
  bumpy::Float32    # how deep those are
  set::Int          # which of the part's sets of places in the pictures to use, counted from 0
end

const WRAPS = Dict(10497 => 0, 33071 => 1, 33648 => 2)

"The picture that the texture note `t` names, or no picture"
paint(f::File, t) = begin
  t isa Dict || return BARE
  texture = f.json["textures"][Int(t["index"])+1]
  source = get(texture, "source", get(under(under(texture, "extensions"), "EXT_texture_webp"), "source", nothing))
  source === nothing && return BARE
  sampler = haskey(texture, "sampler") ? f.json["samplers"][Int(texture["sampler"])+1] : NONE
  Paint(Int(source) + 1, get(WRAPS, Int(get(sampler, "wrapS", 10497)), 0), get(WRAPS, Int(get(sampler, "wrapT", 10497)), 0))
end

vec3(x) = (Float32(x[1]), Float32(x[2]), Float32(x[3]))

# A part that names no material is a rough grey metal, as the format says
const PLAIN = Material((1f0, 1f0, 1f0), 1f0, 1f0, (0f0, 0f0, 0f0), BARE, BARE, BARE, BARE, 1f0, BARE, 1f0, 0)

Material(f::File, m) = begin
  pbr, more = under(m, "pbrMetallicRoughness"), under(m, "extensions")
  colour, metal, rough = get(pbr, "baseColorFactor", [1, 1, 1, 1]), get(pbr, "metallicFactor", 1), get(pbr, "roughnessFactor", 1)
  base, surface = get(pbr, "baseColorTexture", nothing), get(pbr, "metallicRoughnessTexture", nothing)
  # An older way to say the same: a colour and how glossy it is
  old = under(more, "KHR_materials_pbrSpecularGlossiness")
  if !isempty(old)
    colour, metal, rough = get(old, "diffuseFactor", [1, 1, 1, 1]), 0, 1 - get(old, "glossinessFactor", 1)
    base, surface = get(old, "diffuseTexture", nothing), nothing
  end
  shade, bumps, glowing = get(m, "occlusionTexture", nothing), get(m, "normalTexture", nothing), get(m, "emissiveTexture", nothing)
  strength = Float32(get(under(more, "KHR_materials_emissive_strength"), "emissiveStrength", 1))
  # The part has one set of places for all its pictures here: the set that its first picture names
  first_paint = something((t for t in (base, surface, bumps, shade, glowing) if t isa Dict)..., NONE)
  Material(vec3(colour), Float32(metal), Float32(rough), vec3(get(m, "emissiveFactor", [0, 0, 0])) .* strength,
           paint(f, base), paint(f, surface), paint(f, glowing),
           paint(f, shade), shade isa Dict ? Float32(get(shade, "strength", 1)) : 1f0,
           paint(f, bumps), bumps isa Dict ? Float32(get(bumps, "scale", 1)) : 1f0,
           Int(get(first_paint, "texCoord", 0)))
end

"The bytes of picture `n` of the file, a PNG or a JPEG, or none if they can't be found"
picture(f::File, n) = try
  image = f.json["images"][n]
  haskey(image, "uri") && return bytes_at(f, image["uri"])
  v = f.json["bufferViews"][Int(image["bufferView"])+1]
  from = Int(get(v, "byteOffset", 0))
  buffer(f, v["buffer"])[from+1:from+Int(v["byteLength"])]
catch
  UInt8[]
end

# --- the model -----------------------------------------------------------------

"""
The triangles of a glTF file, with z up, and what each is made of. A list that
no part of the file gives is empty: `normals`, `places` and `tints`.
"""
mutable struct Model
  points::Vector{Vec}             # three corners for each triangle
  normals::Vector{Vec}            # the way the surface faces at each corner, for a curve that looks smooth. (0, 0, 0) where the file doesn't say.
  places::Vector{UV}              # where each corner is in the material's pictures: (0, 0) is a picture's top left, (1, 1) its bottom right
  tints::Vector{Vec}              # a colour for each corner, which the material's colour is multiplied by
  made_of::Vector{Int32}          # for each triangle, which of `materials`
  materials::Vector{Material}     # the first is for a part that names none
  pictures::Vector{Vector{UInt8}} # the file's pictures as PNG or JPEG bytes. One that nothing uses is empty.
  sky::Int                        # which of `pictures` shows the whole sky round the model, or 0 for none
  sun::Vec                        # the way to the light that shines on the model, or (0, 0, 0) for none
  sunlight::Vec                   # how much red, green and blue light it gives
end

Model(points, normals, places, tints, made_of, materials, pictures) =
  Model(points, normals, places, tints, made_of, materials, pictures, 0, (0f0, 0f0, 0f0), (0f0, 0f0, 0f0))
Model() = Model(Vec[], Vec[], UV[], Vec[], Int32[], Material[PLAIN], Vector{UInt8}[])

"Make `list` as long as `points`, with `blank` for the corners it has nothing for"
pad!(list::Vector{T}, points, blank::T) where T = (n = length(list); resize!(list, length(points)); list[n+1:end] .= Ref(blank); list)

"The corners of a part's triangles, in order, from the row of corners that the file gives"
triangles(order::Vector{Int}, mode) = begin
  mode == 4 && return order[1:3*(length(order)÷3)]
  out = Int[]
  for i in 1:length(order)-2
    # A strip makes a triangle of each three in a row, turned the other way each time. A fan shares its first corner.
    append!(out, mode == 6 ? (order[1], order[i+1], order[i+2]) : isodd(i) ? (order[i], order[i+1], order[i+2]) : (order[i+1], order[i], order[i+2]))
  end
  out
end

moved(m::Matrix{Float64}, p, i) = begin
  x, y, z = Float64(p[1, i]), Float64(p[2, i]), Float64(p[3, i])
  (Float32(m[1, 1] * x + m[1, 2] * y + m[1, 3] * z + m[1, 4]),
   Float32(m[2, 1] * x + m[2, 2] * y + m[2, 3] * z + m[2, 4]),
   Float32(m[3, 1] * x + m[3, 2] * y + m[3, 3] * z + m[3, 4]))
end

turned(m::Matrix{Float64}, p, i) = begin
  x, y, z = Float64(p[1, i]), Float64(p[2, i]), Float64(p[3, i])
  n = (m[1, 1] * x + m[1, 2] * y + m[1, 3] * z, m[2, 1] * x + m[2, 2] * y + m[2, 3] * z, m[3, 1] * x + m[3, 2] * y + m[3, 3] * z)
  len = sqrt(n[1]^2 + n[2]^2 + n[3]^2)
  len > 0 ? Float32.(n ./ len) : (0f0, 0f0, 0f0)
end

"Add one part of a mesh to `out`, placed by the matrix `m`"
add!(out::Model, f::File, part, m::Matrix{Float64}) = begin
  haskey(under(part, "extensions"), "KHR_draco_mesh_compression") && throw(Unreadable("The model is packed with Draco, which this viewer doesn't unpack"))
  mode, given = Int(get(part, "mode", 4)), under(part, "attributes")
  # Only triangles show. A part can be points or lines too.
  (mode in (4, 5, 6) && haskey(given, "POSITION")) || return out
  at = numbers(f, given["POSITION"])
  size(at, 1) == 3 || return out
  count = size(at, 2)
  order = haskey(part, "indices") ? vec(numbers(f, part["indices"], Int)) .+ 1 : collect(1:count)
  corners = triangles(order, mode)
  all(i -> 1 <= i <= count, corners) || error("A triangle names a corner that the file doesn't have")
  material = haskey(part, "material") ? Int(part["material"]) + 2 : 1
  1 <= material <= length(out.materials) || (material = 1)
  column(name, wide) = begin
    haskey(given, name) || return nothing
    x = numbers(f, given[name])
    size(x, 1) >= wide && size(x, 2) == count ? x : nothing
  end
  normals, tints = column("NORMAL", 3), column("COLOR_0", 3)
  places = column("TEXCOORD_$(out.materials[material].set)", 2)
  normals === nothing || pad!(out.normals, out.points, (0f0, 0f0, 0f0))
  places === nothing || pad!(out.places, out.points, (0f0, 0f0))
  tints === nothing || pad!(out.tints, out.points, (1f0, 1f0, 1f0))
  face = facing(m)
  for i in corners
    push!(out.points, moved(m, at, i))
    normals === nothing || push!(out.normals, turned(face, normals, i))
    places === nothing || push!(out.places, (places[1, i], places[2, i]))
    tints === nothing || push!(out.tints, (tints[1, i], tints[2, i], tints[3, i]))
  end
  append!(out.made_of, fill(Int32(material), length(corners) ÷ 3))
  out
end

"Note the light that node `n` holds, if it shines one way and is the first that does. It shines along the node's -z."
shine!(out::Model, f::File, n, m::Matrix{Float64}) = begin
  out.sunlight == (0f0, 0f0, 0f0) || return out
  lights = get(under(under(f.json, "extensions"), "KHR_lights_punctual"), "lights", [])
  0 <= n < length(lights) || return out
  light = lights[Int(n)+1]
  get(light, "type", "") == "directional" || return out
  to = (m[1, 3], m[2, 3], m[3, 3])
  len = sqrt(to[1]^2 + to[2]^2 + to[3]^2)
  len > 0 || return out
  out.sun = Float32.(to ./ len)
  out.sunlight = vec3(get(light, "color", [1, 1, 1])) .* Float32(get(light, "intensity", 1))
  out
end

"Add the mesh of node `n`, and of each node under it"
walk!(out::Model, f::File, n, above::Matrix{Float64}, deep=1) = begin
  deep > 200 && error("The nodes go round in a ring")
  node = f.json["nodes"][Int(n)+1]
  m = times(above, matrix(node))
  if haskey(node, "mesh")
    for part in get(f.json["meshes"][Int(node["mesh"])+1], "primitives", []); add!(out, f, part, m) end
  end
  light = get(under(under(node, "extensions"), "KHR_lights_punctual"), "light", nothing)
  light isa Real && shine!(out, f, Int(light), m)
  for child in get(node, "children", []); walk!(out, f, child, m, deep + 1) end
  out
end

"The model in the .glb or .gltf file at `path`"
model(path::AbstractString) = model(File(path))

"The model that `bytes` holds, as a .glb file has them. Code that makes a model gives it this way, with no file."
model(bytes::Vector{UInt8}) = model(File(bytes))

model(f::File) = begin
  g = f.json
  out = Model()
  append!(out.materials, [Material(f, m) for m in get(g, "materials", [])])
  nodes = get(g, "nodes", [])
  # A file can hold several scenes and says which one to show. One with no scene shows every node that isn't under another.
  scenes = get(g, "scenes", [])
  scene = isempty(scenes) ? NONE : scenes[clamp(Int(get(g, "scene", 0)) + 1, 1, length(scenes))]
  roots = if isempty(scenes)
    under_another = Set(Int(c) for node in nodes for c in get(node, "children", []))
    [i for i in 0:length(nodes)-1 if !(i in under_another)]
  else
    get(scene, "nodes", [])
  end
  sky = get(under(under(scene, "extras"), "sky"), "image", nothing)
  sky isa Real && 0 <= sky < length(get(g, "images", [])) && (out.sky = Int(sky) + 1)
  for n in roots; walk!(out, f, n, UPRIGHT) end
  isempty(out.normals) || pad!(out.normals, out.points, (0f0, 0f0, 0f0))
  isempty(out.places) || pad!(out.places, out.points, (0f0, 0f0))
  isempty(out.tints) || pad!(out.tints, out.points, (1f0, 1f0, 1f0))
  # Only the pictures of materials that some triangle is made of are needed
  used = Set(Int.(out.made_of))
  wanted = Set(p.image for (i, m) in enumerate(out.materials) if i in used for p in (m.base, m.surface, m.glowing, m.shade, m.bumps))
  push!(wanted, out.sky)
  append!(out.pictures, [i in wanted ? picture(f, i) : UInt8[] for i in 1:length(get(g, "images", []))])
  out
end

export model, Model, Material, Paint, Unreadable
