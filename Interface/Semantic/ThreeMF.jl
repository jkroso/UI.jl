# Reads the triangles of a 3MF file, the kind of file that a slicer for a 3D
# printer saves. The file is a zip. In it are one or more parts written in XML.
# A part has objects. An object is a mesh, with corners and triangles, or it's
# made of other objects, each moved and turned by a transform. One part lists
# the objects to build:
#
#     points("bracket.3mf")   # three corners for each triangle
#
# The zip is unpacked here, with no library, so that an app needs nothing more
# to read one.

const Vec = NTuple{3,Float32}

# --- the zip -------------------------------------------------------------------
#
# A zip ends with a list of its files: each one's name, how it was packed and
# where it starts. A file is stored as it is, or packed with "deflate".

u16(b, i) = UInt16(b[i+1]) | UInt16(b[i+2]) << 8
u32(b, i) = UInt32(u16(b, i)) | UInt32(u16(b, i + 2)) << 16
u64(b, i) = UInt64(u32(b, i)) | UInt64(u32(b, i + 4)) << 32

# A number that's too big for its 4 bytes is written as this, and the true number is somewhere else
const BIG = 0xffffffff

"Where a file of a zip is, and how to unpack it"
struct Entry
  packed::Bool   # with deflate
  at::Int        # where its header starts, counted from 0
  size::Int      # in the zip
  full::Int      # once it's unpacked
end

"Each file in the zip `bytes`, by name"
entries(bytes::Vector{UInt8}) = begin
  # The list's own place is at the end of the zip, before a comment that's usually empty
  tail = length(bytes) - 22
  while tail >= 0 && u32(bytes, tail) != 0x06054b50; tail -= 1 end
  tail < 0 && error("not a zip")
  n, at = Int(u16(bytes, tail + 10)), Int(u32(bytes, tail + 16))
  if (n == 0xffff || at == BIG) && tail >= 20 && u32(bytes, tail - 20) == 0x07064b50
    # A big zip has a second, longer note of where its list is
    long = Int(u64(bytes, tail - 20 + 8))
    n, at = Int(u64(bytes, long + 32)), Int(u64(bytes, long + 48))
  end
  out = Dict{String,Entry}()
  for _ in 1:n
    u32(bytes, at) == 0x02014b50 || error("not a zip")
    method = u16(bytes, at + 10)
    name, extra, comment = Int(u16(bytes, at + 28)), Int(u16(bytes, at + 30)), Int(u16(bytes, at + 32))
    size, full, start = u32(bytes, at + 20), u32(bytes, at + 24), u32(bytes, at + 42)
    if BIG in (size, full, start)
      # The numbers that didn't fit are in the entry's extra fields, in the one with the id 1
      field, stop = at + 46 + name, at + 46 + name + extra
      while field + 4 <= stop && u16(bytes, field) != 0x0001; field += 4 + u16(bytes, field + 2) end
      field + 4 <= stop || error("not a zip")
      next() = (field += 8; u64(bytes, field - 4))
      full == BIG && (full = next())
      size == BIG && (size = next())
      start == BIG && (start = next())
    end
    method in (0, 8) && (out[String(bytes[at+47:at+46+name])] = Entry(method == 8, Int(start), Int(size), Int(full)))
    at += 46 + name + extra + comment
  end
  out
end

"The bytes of one file of the zip"
unpack(bytes::Vector{UInt8}, e::Entry) = begin
  u32(bytes, e.at) == 0x04034b50 || error("not a zip")
  from = e.at + 30 + u16(bytes, e.at + 26) + u16(bytes, e.at + 28)
  data = view(bytes, from+1:from+e.size)
  e.packed ? inflate(data, e.full) : Vector{UInt8}(data)
end

# --- deflate -------------------------------------------------------------------
#
# Packed data is a row of blocks. A block is a run of codes: a code is one
# byte, or it says "the `length` bytes that came `distance` bytes ago, again".
# Common codes take fewer bits. Each block says how many bits each code takes,
# or uses a fixed set of lengths.

"Reads the bits of `data`, the first bit of each byte first"
mutable struct Bits{T<:AbstractVector{UInt8}}
  data::T
  at::Int       # the next byte to read
  held::UInt64  # bits that were read and not yet taken
  count::Int    # how many of them there are
end

# Past the end of the data the bits are 0. Data that's cut short then fails when a code makes no sense.
more!(b::Bits, n) = while b.count < n
  b.held |= UInt64(b.at <= length(b.data) ? b.data[b.at] : 0x00) << b.count
  b.at += 1
  b.count += 8
end

bits!(b::Bits, n) = begin
  n == 0 && return 0
  more!(b, n)
  v = Int(b.held & ((UInt64(1) << n) - 1))
  b.held >>= n
  b.count -= n
  v
end

"The codes of one alphabet. `table[bits + 1]` is a symbol and its length in bits, for the next `width` bits of the data."
struct Codes
  table::Vector{UInt16}
  width::Int
end

"The codes for an alphabet in which symbol `i - 1` takes `lengths[i]` bits, or 0 if it isn't used"
Codes(lengths::AbstractVector{<:Integer}) = begin
  width = max(1, maximum(lengths))
  table = zeros(UInt16, 1 << width)
  code = 0
  # Shorter codes come first, and symbols with the same length are in order
  for len in 1:width
    for (i, l) in enumerate(lengths)
      l == len || continue
      # The data has the code's first bit first, so the table is looked up with its bits the other way round
      turned = Int(bitreverse(UInt16(code)) >> (16 - len))
      for k in turned:(1<<len):(1<<width)-1
        table[k+1] = UInt16((i - 1) << 4 | len)
      end
      code += 1
    end
    code <<= 1
  end
  Codes(table, width)
end

symbol!(b::Bits, c::Codes) = begin
  more!(b, c.width)
  found = c.table[(b.held & ((UInt64(1) << c.width) - 1)) + 1]
  len = Int(found & 0x0f)
  len == 0 && error("bad code")
  b.held >>= len
  b.count -= len
  Int(found >> 4)
end

const LENGTHS = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258)
const LENGTH_BITS = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0)
const DISTANCES = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                   4097, 6145, 8193, 12289, 16385, 24577)
const DISTANCE_BITS = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13)
# The order in which a block gives the lengths of the codes that its other lengths are written in
const ORDER = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15)
const FIXED = (Codes([fill(8, 144); fill(9, 112); fill(7, 24); fill(8, 8)]), Codes(fill(5, 30)))

"The codes that a block gives for itself: one alphabet for bytes and lengths, one for distances"
codes!(b::Bits) = begin
  bytes, distances, n = bits!(b, 5) + 257, bits!(b, 5) + 1, bits!(b, 4) + 4
  given = zeros(Int, 19)
  for i in 1:n
    given[ORDER[i]+1] = bits!(b, 3)
  end
  inner = Codes(given)
  lengths = Int[]
  while length(lengths) < bytes + distances
    s = symbol!(b, inner)
    if s < 16
      push!(lengths, s)
    elseif s == 16
      append!(lengths, fill(lengths[end], 3 + bits!(b, 2)))
    else
      append!(lengths, zeros(Int, s == 17 ? 3 + bits!(b, 3) : 11 + bits!(b, 7)))
    end
  end
  Codes(view(lengths, 1:bytes)), Codes(view(lengths, bytes+1:bytes+distances))
end

"Unpack `data`, which is `n` bytes when it's unpacked"
inflate(data::AbstractVector{UInt8}, n::Integer) = begin
  out = Vector{UInt8}(undef, n)
  b = Bits(data, 1, UInt64(0), 0)
  at = 0
  while true
    final, kind = bits!(b, 1) == 1, bits!(b, 2)
    if kind == 0
      # A block that isn't packed starts at the next whole byte, with its length written twice
      bits!(b, b.count % 8)
      len = bits!(b, 16)
      bits!(b, 16)
      for _ in 1:len
        out[at+=1] = bits!(b, 8)
      end
    else
      kind == 3 && error("bad block")
      main, far = kind == 1 ? FIXED : codes!(b)
      while true
        s = symbol!(b, main)
        if s < 256
          out[at+=1] = s
        elseif s == 256
          break
        else
          len = LENGTHS[s-256] + bits!(b, LENGTH_BITS[s-256])
          d = symbol!(b, far) + 1
          back = DISTANCES[d] + bits!(b, DISTANCE_BITS[d])
          # A byte at a time: the bytes to copy can run into the bytes being written
          for _ in 1:len
            out[at+1] = out[at+1-back]
            at += 1
          end
        end
      end
    end
    final && break
  end
  at == n || error("wrong size")
  out
end

# --- the model -------------------------------------------------------------------

# Where a point goes: twelve numbers, as the 3MF file writes them. The first
# nine turn and stretch it, and the last three move it.
const Transform = NTuple{12,Float32}
const STILL = Transform((1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0))

move(t::Transform, (x, y, z)) = (x * t[1] + y * t[4] + z * t[7] + t[10],
                                 x * t[2] + y * t[5] + z * t[8] + t[11],
                                 x * t[3] + y * t[6] + z * t[9] + t[12])

"The transform that does `a` and then `b`"
then(a::Transform, b::Transform) = begin
  row(i) = (a[i] * b[1] + a[i+1] * b[4] + a[i+2] * b[7],
            a[i] * b[2] + a[i+1] * b[5] + a[i+2] * b[8],
            a[i] * b[3] + a[i+1] * b[6] + a[i+2] * b[9])
  Transform((row(1)..., row(4)..., row(7)..., move(b, (a[10], a[11], a[12]))...))
end

"One object of a part: a mesh, or other objects that each have a transform"
struct Object
  corners::Vector{Vec}
  triangles::Vector{NTuple{3,Int}}                 # each one's corners, counted from 0
  made_of::Vector{Tuple{String,String,Transform}}  # the part that has each object, its id there, and where it goes
end

Object() = Object(Vec[], NTuple{3,Int}[], Tuple{String,String,Transform}[])

"What one part of the file holds: its objects by id, and the objects it says to build"
struct Part
  objects::Dict{String,Object}
  build::Vector{Tuple{String,String,Transform}}
end

"""
Call `f(name, attributes)` for each tag that opens in the XML `text`, in
order. `attributes` is the text between the tag's name and its end.
"""
tags(f, text::String) = begin
  bytes, n = codeunits(text), ncodeunits(text)
  i = 1
  while i < n
    bytes[i] == UInt8('<') || (i += 1; continue)
    c = bytes[i+1]
    if c == UInt8('!') && startswith(SubString(text, i), "<!--")
      # Nothing in a comment is a tag
      i = something(findnext("-->", text, i), n:n)[end] + 1
      continue
    end
    # A > can be in the value of an attribute, so the tag ends at the first one that isn't in quotes
    j, quoted = i + 1, 0x00
    while j <= n && (quoted != 0x00 || bytes[j] != UInt8('>'))
      b = bytes[j]
      if quoted != 0x00
        b == quoted && (quoted = 0x00)
      elseif b == UInt8('"') || b == UInt8('\'')
        quoted = b
      end
      j += 1
    end
    if c != UInt8('/') && c != UInt8('?') && c != UInt8('!')
      k = i + 1
      while k < j && !(bytes[k] in (UInt8(' '), UInt8('\t'), UInt8('\n'), UInt8('\r'), UInt8('/'))); k += 1 end
      f(SubString(text, i + 1, prevind(text, k)), SubString(text, k, prevind(text, min(j, n + 1))))
    end
    i = j + 1
  end
end

"The pattern that finds the value of the attribute `name`, with a prefix like `p:` or with none"
pattern(name) = Regex("(?:^|[\\s:])$name\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")

const PATTERNS = Dict(name => pattern(name) for name in ("id", "objectid", "path", "transform", "x", "y", "z", "v1", "v2", "v3", "Target", "Type"))
# A corner and a triangle as nearly every file writes them. One pattern for all three numbers is quicker than three.
const CORNER = r"^\s*x=\"([^\"]*)\"\s+y=\"([^\"]*)\"\s+z=\"([^\"]*)\""
const TRIANGLE = r"^\s*v1=\"(\d+)\"\s+v2=\"(\d+)\"\s+v3=\"(\d+)\""

"The value of the attribute `name`, or nothing if the tag doesn't have it"
value(attributes, name) = begin
  m = match(PATTERNS[name], attributes)
  m === nothing ? nothing : something(m[1], m[2])
end

number(attributes, name) = parse(Float32, something(value(attributes, name), "0"))

transform(attributes) = begin
  text = value(attributes, "transform")
  text === nothing && return STILL
  numbers = parse.(Float32, split(text))
  length(numbers) == 12 ? Transform(Tuple(numbers)) : STILL
end

"The name of a file in the zip for a path that the XML gives, like `/3D/Objects/object_1.model`"
name_of(path) = String(lstrip(path, '/'))

"The objects and the build list in the XML of the part at `path`"
Part(text::String, path::String) = begin
  part = Part(Dict{String,Object}(), Tuple{String,String,Transform}[])
  object = Ref(Object())   # the object whose tags are being read
  tags(text) do name, attributes
    if name == "vertex"
      m = match(CORNER, attributes)
      push!(object[].corners, m === nothing ? (number(attributes, "x"), number(attributes, "y"), number(attributes, "z")) :
                                            (parse(Float32, m[1]), parse(Float32, m[2]), parse(Float32, m[3])))
    elseif name == "triangle"
      m = match(TRIANGLE, attributes)
      push!(object[].triangles, m === nothing ? ntuple(k -> parse(Int, value(attributes, "v$k")), 3) :
                                              (parse(Int, m[1]), parse(Int, m[2]), parse(Int, m[3])))
    elseif name == "object"
      object[] = part.objects[something(value(attributes, "id"), "")] = Object()
    elseif name == "component"
      # An object that this object is made of can be in another part of the file
      push!(object[].made_of, (name_of(something(value(attributes, "path"), path)), something(value(attributes, "objectid"), ""), transform(attributes)))
    elseif name == "item"
      push!(part.build, (name_of(something(value(attributes, "path"), path)), something(value(attributes, "objectid"), ""), transform(attributes)))
    end
  end
  part
end

const DEEPEST = 16   # objects in objects. A file whose objects are made of each other stops there.

"""
The corners of the triangles in the 3MF file at `path`, three for each
triangle, with each object where the file says to build it.
"""
points(path::AbstractString) = begin
  bytes = read(path)
  files = entries(bytes)
  parts = Dict{String,Part}()
  part(name) = get!(() -> Part(String(unpack(bytes, files[name])), name), parts, name)
  out = Vec[]
  add(name, id, t, depth) = begin
    object = get(part(name).objects, id, nothing)
    (object === nothing || depth > DEEPEST) && return
    n = length(object.corners)
    for corners in object.triangles
      all(c -> 0 <= c < n, corners) || continue
      foreach(c -> push!(out, move(t, object.corners[c+1])), corners)
    end
    foreach(((name, id, inner),) -> add(name, id, then(inner, t), depth + 1), object.made_of)
  end
  main = part(root(bytes, files))
  # A file with no build list shows every object of its main part
  build = isempty(main.build) ? [(root(bytes, files), id, STILL) for id in keys(main.objects)] : main.build
  foreach(((name, id, t),) -> add(name, id, t, 1), build)
  out
end

"The name of the part that lists what to build. The zip's own list of what's in it says which one that is."
root(bytes, files) = begin
  found = Ref{Union{Nothing,String}}(nothing)
  haskey(files, "_rels/.rels") && tags(String(unpack(bytes, files["_rels/.rels"]))) do name, attributes
    name == "Relationship" && endswith(something(value(attributes, "Type"), ""), "/3dmodel") &&
      (found[] = name_of(something(value(attributes, "Target"), "")))
  end
  found[] !== nothing && haskey(files, found[]) && return found[]
  haskey(files, "3D/3dmodel.model") && return "3D/3dmodel.model"
  first(sort!(filter(endswith(".model"), collect(keys(files)))))
end

export points
