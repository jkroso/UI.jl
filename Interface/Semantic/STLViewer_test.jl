@use Test: @test
@use "github.com/jkroso/MiniFB.jl" Window Keys KeyPress KeyRelease onkey onscroll
@use "github.com/jkroso/Font.jl/units" px
@use GeometryBasics: Vec2
@use "../Geometric"...
@use "../draw" frame rect
@use "../testing"...
@use "./STLViewer" STLViewer Mesh read_stl triangles rough Vec

# A box 20 wide, 30 deep and 40 tall, as 12 triangles
const corners = [(x, y, z) for z in (0f0, 40f0), y in (0f0, 30f0), x in (0f0, 20f0)]   # corners[z, y, x]
const sides = [(1, 3, 4, 2), (5, 6, 8, 7), (1, 2, 6, 5), (3, 7, 8, 4), (1, 5, 7, 3), (2, 4, 8, 6)]
const box = [corners[i] for (a, b, c, d) in sides for i in (a, b, c, a, c, d)]

"Write `points`, three for each triangle, as an STL file in its binary form"
binary(path, points) = open(path, "w") do io
  write(io, zeros(UInt8, 80), UInt32(length(points) ÷ 3))
  for i in 1:3:length(points)
    write(io, 0f0, 0f0, 0f0)
    foreach(p -> write(io, p...), points[i:i+2])
    write(io, UInt16(0))
  end
end

"Write them in its text form"
text(path, points) = open(path, "w") do io
  println(io, "solid box")
  for i in 1:3:length(points)
    println(io, " facet normal 0 0 0\n  outer loop")
    foreach(p -> println(io, "   vertex ", join(p, " ")), points[i:i+2])
    println(io, "  endloop\n endfacet")
  end
  println(io, "endsolid box")
end

const dir = mktempdir()
binary(joinpath(dir, "box.stl"), box)
text(joinpath(dir, "text.stl"), box)
write(joinpath(dir, "notes.stl"), "This isn't a model")

# Both forms of the file give the same model
let a = read_stl(joinpath(dir, "box.stl")), b = read_stl(joinpath(dir, "text.stl"))
  @test a isa Mesh && b isa Mesh
  @test triangles(a) == triangles(b) == 12
  @test a.size == b.size == (20f0, 30f0, 40f0)
  @test a.corners == b.corners
  # The model fits in a ball of radius 1 round the origin
  @test maximum(p -> sqrt(sum(abs2, p)), a.corners) ≈ 1
end

# A file that's missing, or isn't a model, gives a sentence to show in place of the model
@test read_stl(joinpath(dir, "missing.stl")) isa String
@test read_stl(joinpath(dir, "notes.stl")) isa String

# --- 3MF files -------------------------------------------------------------------
#
# A 3MF file is a zip with XML in it. This one has the box as a mesh in a part
# of its own. The main part builds two of them: one where it is, and one that's
# 100 further along x.

@use "./STLViewer" read_3mf read_model
@use "./ThreeMF" => ThreeMF

const mesh_xml = """
<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
 <resources>
  <!-- <object id="9"><mesh/></object> a comment isn't read -->
  <object id="1" name="a > b" type="model"><mesh>
   <vertices>
$(join(("    <vertex x=\"$(p[1])\" y=\"$(p[2])\" z=\"$(p[3])\"/>" for p in vec(corners)), "\n"))
   </vertices>
   <triangles>
$(join(("    <triangle v1=\"$(a - 1)\" v2=\"$(b - 1)\" v3=\"$(c - 1)\"/>" for (p, q, r, s) in sides for (a, b, c) in ((p, q, r), (p, r, s))), "\n"))
   </triangles>
  </mesh></object>
 </resources>
</model>
"""

const main_xml = """
<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
 <resources>
  <object id="2" type="model"><components>
   <component p:path="/3D/Objects/box.model" objectid="1"/>
   <component p:path="/3D/Objects/box.model" objectid="1" transform="1 0 0 0 1 0 0 0 1 100 0 0"/>
  </components></object>
 </resources>
 <build><item objectid="2" transform="1 0 0 0 1 0 0 0 1 5 5 0"/></build>
</model>
"""

const rels_xml = """
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/main.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""

"Write `files`, each a name and its text, as a zip that stores them as they are"
stored(path, files) = open(path, "w") do io
  places = Int[]
  for (name, text) in files
    push!(places, position(io))
    write(io, 0x04034b50, UInt16(20), UInt16(0), UInt16(0), UInt16(0), UInt16(0), UInt32(0),
          UInt32(sizeof(text)), UInt32(sizeof(text)), UInt16(sizeof(name)), UInt16(0), name, text)
  end
  list = position(io)
  for ((name, text), place) in zip(files, places)
    write(io, 0x02014b50, UInt16(20), UInt16(20), UInt16(0), UInt16(0), UInt16(0), UInt16(0), UInt32(0),
          UInt32(sizeof(text)), UInt32(sizeof(text)), UInt16(sizeof(name)), UInt16(0), UInt16(0), UInt16(0), UInt16(0),
          UInt32(0), UInt32(place), name)
  end
  size = position(io) - list
  write(io, 0x06054b50, UInt16(0), UInt16(0), UInt16(length(files)), UInt16(length(files)), UInt32(size), UInt32(list), UInt16(0))
end

const parts = ["_rels/.rels" => rels_xml, "3D/main.model" => main_xml, "3D/Objects/box.model" => mesh_xml]
stored(joinpath(dir, "boxes.3mf"), parts)

let m = read_3mf(joinpath(dir, "boxes.3mf"))
  @test m isa Mesh
  @test triangles(m) == 24
  # Two boxes 20 wide, the second one 100 along from the first
  @test m.size == (120f0, 30f0, 40f0)
  @test read_model(joinpath(dir, "boxes.3mf")).corners == m.corners
  @test read_model(joinpath(dir, "box.stl")).size == (20f0, 30f0, 40f0)
end

# The files of a zip are packed, most often. The Mac's own `zip` packs them here.
if Sys.which("zip") !== nothing
  folder = mktempdir()
  for (name, text) in parts
    mkpath(dirname(joinpath(folder, name)))
    write(joinpath(folder, name), text)
  end
  packed = joinpath(dir, "packed.3mf")
  cd(() -> run(pipeline(`zip -q -r $packed .`, devnull)), folder)
  let bytes = read(packed), files = ThreeMF.entries(bytes)
    @test files["3D/Objects/box.model"].packed
    @test String(ThreeMF.unpack(bytes, files["3D/Objects/box.model"])) == mesh_xml
  end
  @test read_3mf(packed).corners == read_3mf(joinpath(dir, "boxes.3mf")).corners
end

# A file that isn't a zip, or is missing, gives a sentence
@test read_3mf(joinpath(dir, "notes.stl")) isa String
@test read_3mf(joinpath(dir, "missing.3mf")) isa String

# A viewer shows a 3MF file as it shows an STL file
let v = STLViewer(joinpath(dir, "boxes.3mf")), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  @test v.model isa Mesh && triangles(v.model) == 24
end

# A ball of 90,000 triangles has a rougher copy with no more triangles than it's allowed
let around = 300, up = 150
  at(i, j) = (θ = π * j / up; φ = 2π * i / around; Vec((sin(θ) * cos(φ), sin(θ) * sin(φ), cos(θ))))
  ball = Vec[]
  for i in 0:around-1, j in 0:up-1
    push!(ball, at(i, j), at(i, j + 1), at(i + 1, j + 1), at(i, j), at(i + 1, j + 1), at(i + 1, j))
  end
  m = Mesh(ball)
  @test triangles(m) > 80_000
  r = rough(m, 20_000)
  @test 2000 < triangles(r) <= 20_000
  @test r.size == m.size
end

let v = STLViewer(joinpath(dir, "box.stl")),
    w = Window(Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(20px), v), size=(500px, 440px))
  frame(w)
  @test v.model isa Mesh
  # The picture has the model in its middle and nothing in its corners
  p = v.picture
  pw = round(Int, sqrt(length(p.pixels) * rect(v).children[1].width / rect(v).children[1].height))
  ph = length(p.pixels) ÷ pw
  @test p.pixels[(ph ÷ 2) * pw + pw ÷ 2] >> 24 == 0xff
  @test p.pixels[1] == p.pixels[end] == 0

  # A drag to the right turns the model, half a degree for each px, and a drag down tilts it
  turn, tilt, was = v.turn, v.tilt, copy(p.pixels)
  at = move!(w, v)
  w.keys |= Keys.mouse_left
  onkey(w, KeyPress{Keys.mouse_left}(0, w))
  move!(w, (at[1] + 40px, at[2] + 20px))
  w.keys ⊻= Keys.mouse_left
  onkey(w, KeyRelease{Keys.mouse_left}(0, w))
  @test v.turn ≈ turn + 20
  @test v.tilt ≈ tilt + 10
  # ... and the picture changes with it
  @test v.picture.pixels != was
  # The mouse doesn't turn it once the button is up
  move!(w, (at[1], at[2]))
  @test v.turn ≈ turn + 20

  # Scrolling makes it bigger only while ⌘ is held
  move!(w, v)
  onscroll(w, Vec2{px}(0px, 2px))
  @test v.zoom == 1
  holding(() -> onscroll(w, Vec2{px}(0px, 2px)), w, (Keys.cmd,))
  @test v.zoom > 1

  # Two clicks put it back as it was at first
  click!(w, v)
  click!(w, v)
  @test (v.turn, v.tilt, v.zoom) == (turn, tilt, 1.0)

  # The arrow keys turn it once it has the keyboard
  press!(w, Keys.right)
  @test v.turn ≈ turn + 10
end

# A viewer of a file that isn't there says so, and draws without a model
let v = STLViewer(joinpath(dir, "missing.stl")), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  @test v.model isa String
  @test rect(v) !== nothing
end
