@use Test: @test
@use "github.com/jkroso/MiniFB.jl" Window Keys KeyPress KeyRelease onkey onscroll
@use "github.com/jkroso/Font.jl/units" px
@use GeometryBasics: Vec2
@use "../Geometric"...
@use "../draw" frame rect onpinch
@use "../testing"...
@use "./STLViewer" STLViewer Mesh read_stl read_gltf triangles rough Vec show!
@use "./GLTF" => GLTF
@use "./STLViewer" => stl
@use Base64: base64encode
@use Skia

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

  # A pinch on the trackpad makes it bigger or smaller, with no key held
  big = v.zoom
  onpinch(w, 1.25)
  @test v.zoom ≈ big * 1.25
  onpinch(w, 0.8)
  @test v.zoom ≈ big

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

# --- glTF files ------------------------------------------------------------------
#
# A .glb file is a text in JSON, then the bytes that the text describes. This
# one has the box as a mesh of 8 corners, with a list that says which three
# make each triangle. It's made of a red plastic. Two nodes show it: one where
# it is, and one that's 100 higher. In a glTF file y is up.

"Write the JSON `text` and the bytes `bin` as a .glb file"
glb(path, text, bin) = open(path, "w") do io
  pad(n) = (4 - n % 4) % 4
  a, b = sizeof(text) + pad(sizeof(text)), length(bin) + pad(length(bin))
  write(io, 0x46546c67, UInt32(2), UInt32(12 + 8 + a + 8 + b))
  write(io, UInt32(a), 0x4e4f534a, text, fill(UInt8(' '), pad(sizeof(text))))
  write(io, UInt32(b), 0x004e4942, bin, zeros(UInt8, pad(length(bin))))
end

"The bytes of numbers, one after another"
bytes(numbers...) = (io = IOBuffer(); foreach(n -> write(io, n), numbers); take!(io))

const box_bytes = bytes((x for p in vec(corners) for x in p)..., (UInt16(i - 1) for (a, b, c, d) in sides for i in (a, b, c, a, c, d))...)

"The text of the box's file. `buffer` is what it says of its bytes, after how many there are."
box_text(buffer="") = """
{"asset": {"version": "2.0", "generator": "a \\"test\\" caf\\u00e9\\n"},
 "scene": 0, "scenes": [{"nodes": [0, 1]}],
 "nodes": [{"mesh": 0}, {"mesh": 0, "translation": [0, 100, 0]}],
 "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
 "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1], "metallicFactor": 0, "roughnessFactor": 0.5}}],
 "accessors": [{"bufferView": 0, "componentType": 5126, "count": 8, "type": "VEC3"},
               {"bufferView": 1, "componentType": 5123, "count": 36, "type": "SCALAR"}],
 "bufferViews": [{"buffer": 0, "byteLength": 96}, {"buffer": 0, "byteOffset": 96, "byteLength": 72}],
 "buffers": [{"byteLength": 168$buffer}]}
"""

glb(joinpath(dir, "box.glb"), box_text(), box_bytes)

let m = read_gltf(joinpath(dir, "box.glb"))
  @test m isa Mesh
  @test triangles(m) == 24
  # The box is 20 wide, 30 tall and 40 deep in its file. The viewer has z up, so its height comes last.
  @test m.size == (20f0, 40f0, 130f0)
  @test maximum(p -> sqrt(sum(abs2, p)), m.corners) ≈ 1
  # It says what the box is made of
  @test m.look !== nothing
  @test all(==(2), m.look.made_of) && length(m.look.made_of) == 24
  let red = m.look.materials[2]
    @test red.colour == (1f0, 0f0, 0f0) && red.metal == 0 && red.rough == 0.5f0
  end
  @test read_model(joinpath(dir, "box.glb")).corners == m.corners
  # An STL file says nothing of that
  @test read_stl(joinpath(dir, "box.stl")).look === nothing
end

# A .gltf file is only the text. Its bytes are in a file that it names, or in the text itself in base64.
write(joinpath(dir, "box bytes.bin"), box_bytes)
write(joinpath(dir, "beside.gltf"), box_text(""", "uri": "box%20bytes.bin" """))
write(joinpath(dir, "inside.gltf"), box_text(""", "uri": "data:application/octet-stream;base64,$(base64encode(box_bytes))" """))
let m = read_gltf(joinpath(dir, "box.glb"))
  @test read_model(joinpath(dir, "beside.gltf")).corners == m.corners
  @test read_model(joinpath(dir, "inside.gltf")).corners == m.corners
end

# A file that's packed in a way the viewer doesn't unpack says which way
glb(joinpath(dir, "packed.glb"), replace(box_text(), "\"scene\"" => "\"extensionsRequired\": [\"KHR_draco_mesh_compression\"], \"scene\""), box_bytes)
@test occursin("Draco", read_gltf(joinpath(dir, "packed.glb")))
# A file that isn't a model, one that's cut short and one that's missing give a sentence too
@test read_gltf(joinpath(dir, "notes.stl")) isa String
glb(joinpath(dir, "short.glb"), box_text(), box_bytes[1:100])
@test read_gltf(joinpath(dir, "short.glb")) isa String
@test read_gltf(joinpath(dir, "missing.glb")) isa String

"The picture of the viewer `v` as a matrix of 0xAARRGGBB, a row for each row of pixels"
picture(v) = begin
  p, area = v.picture, rect(v).children[1]
  pw = round(Int, sqrt(length(p.pixels) * area.width / area.height))
  permutedims(reshape(p.pixels, pw, :))
end
red(p) = Int(p >> 16 & 0xff); green(p) = Int(p >> 8 & 0xff); blue(p) = Int(p & 0xff)

# A viewer shows the box in its own colour, not in the viewer's
let v = STLViewer(joinpath(dir, "box.glb")), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  @test v.model isa Mesh && triangles(v.model) == 24
  p = picture(v)
  drawn = p[permutedims(reshape(v.picture.which, size(p, 2), :)) .!= 0]
  @test length(drawn) > length(p) ÷ 50
  @test all(x -> red(x) > 2green(x) && red(x) > 2blue(x), drawn)
  @test maximum(red, drawn) > 150
  # Behind the model is a grey wall, darker at the top, so that a white part and a dark part both show on any page
  wall = p[permutedims(reshape(v.picture.which, size(p, 2), :)) .== 0]
  @test all(x -> x >> 24 == 0xff && red(x) == green(x) == blue(x), wall)
  @test 60 < red(p[1, 1]) < red(p[end, end]) < 200
end

# A model with no materials has nothing behind it but the page
let v = STLViewer(joinpath(dir, "box.stl")), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  @test picture(v)[1, 1] == picture(v)[end, end] == 0
end

# A model with materials is drawn with fewer pixels while it turns, and in full again when it stops
let v = STLViewer(joinpath(dir, "box.glb"), height=1100px), w = Window(Box(width(1200px), v), size=(1300px, 1300px))
  frame(w)
  still = length(v.picture.pixels)
  click!(w, v)
  press!(w, Keys.right)
  @test length(v.picture.pixels) < still
  v.moved = 0.0
  frame(w)
  @test length(v.picture.pixels) == still
end

# The model grows towards the mouse, so the part under the mouse stays under it. A drag then turns the model
# round the part that was pressed. As the model gets small again, the part under the mouse stays under it too.
let v = STLViewer(joinpath(dir, "box.glb")), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  area = rect(v).children[1]
  # A place on the lower box, left of the middle of the view and below it
  at = (area.left + area.width / 2 - 20px, area.top + area.height / 2 + 100px)
  from = stl.from_middle(area, at)
  part = stl.point(v, area, from)
  @test all(isapprox.(stl.place(v, area, part), from, atol=0.01))
  move!(w, at)
  holding(() -> onscroll(w, Vec2{px}(0px, 5px)), w, (Keys.cmd,))
  @test v.zoom > 1.5 && v.shift != (0.0, 0.0)
  @test all(isapprox.(stl.place(v, area, part), from, atol=0.01))
  # The part is on the box's surface, so a press there finds the same part
  frame(w)
  let p = picture(v), x = p[round(Int, end / 2 + from[2] * size(p, 1) / area.height.value), round(Int, end / 2 + from[1] * size(p, 2) / area.width.value)]
    @test red(x) > 2green(x)
  end
  w.keys |= Keys.mouse_left
  onkey(w, KeyPress{Keys.mouse_left}(0, w))
  @test all(isapprox.(v.pivot, part, atol=0.02))
  move!(w, (at[1] + 60px, at[2] - 30px))
  w.keys ⊻= Keys.mouse_left
  onkey(w, KeyRelease{Keys.mouse_left}(0, w))
  @test v.turn ≈ 35 + 30 && v.tilt ≈ 22 - 15
  @test all(isapprox.(stl.place(v, area, v.pivot), from, atol=0.01))
  under = stl.from_middle(area, w.mouse)
  part = stl.point(v, area, under)
  holding(() -> onscroll(w, Vec2{px}(0px, -30px)), w, (Keys.cmd,))
  @test v.zoom == stl.SMALLEST
  @test all(isapprox.(stl.place(v, area, part), under, atol=0.01))
  # The mouse that stays in one place makes it bigger and smaller again, and it's back where it was
  was = v.shift
  holding(() -> onscroll(w, Vec2{px}(0px, 8px)), w, (Keys.cmd,))
  holding(() -> onscroll(w, Vec2{px}(0px, -8px)), w, (Keys.cmd,))
  @test all(isapprox.(v.shift, was, atol=1e-9))
end

# ⇧ and a drag move the model across the view, as far as the mouse moves, and so does a drag with the middle
# button. Neither turns it. On a page, two fingers on the trackpad scroll the page and leave the model alone.
let v = STLViewer(joinpath(dir, "box.glb")), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  turn, tilt = v.turn, v.tilt
  at = move!(w, v)
  holding(w, (Keys.shft,)) do
    w.keys |= Keys.mouse_left
    onkey(w, KeyPress{Keys.mouse_left}(0, w))
    move!(w, (at[1] + 30px, at[2] - 12px))
    move!(w, (at[1] + 50px, at[2] + 20px))
    w.keys ⊻= Keys.mouse_left
    onkey(w, KeyRelease{Keys.mouse_left}(0, w))
  end
  @test all(isapprox.(v.shift, (50.0, 20.0)))
  @test (v.turn, v.tilt) == (turn, tilt)
  # A drag with ⇧ and ⌘ isn't one with ⇧, so it turns the model
  holding(w, (Keys.shft, Keys.cmd)) do
    w.keys |= Keys.mouse_left
    onkey(w, KeyPress{Keys.mouse_left}(0, w))
    move!(w, (at[1] + 70px, at[2] + 20px))
    w.keys ⊻= Keys.mouse_left
    onkey(w, KeyRelease{Keys.mouse_left}(0, w))
  end
  @test v.turn ≈ turn + 10
  turn, shift = v.turn, v.shift
  w.keys |= Keys.mouse_middle
  onkey(w, KeyPress{Keys.mouse_middle}(0, w))
  move!(w, (at[1] + 40px, at[2] + 30px))
  w.keys ⊻= Keys.mouse_middle
  @test all(isapprox.(v.shift, shift .+ (-30.0, 10.0)))
  @test v.turn == turn
  # Once the button is up, the mouse moves nothing
  move!(w, at)
  @test all(isapprox.(v.shift, shift .+ (-30.0, 10.0)))
  shift, zoom = v.shift, v.zoom
  onscroll(w, Vec2{px}(3px, 2px), false)
  @test (v.shift, v.zoom) == (shift, zoom)
  # A model that's moved a long way stops while the ball round it still reaches the view
  area = rect(v).children[1]
  holding(w, (Keys.shft,)) do
    w.keys |= Keys.mouse_left
    onkey(w, KeyPress{Keys.mouse_left}(0, w))
    move!(w, (at[1] + 5000px, at[2]))
    w.keys ⊻= Keys.mouse_left
    onkey(w, KeyRelease{Keys.mouse_left}(0, w))
  end
  @test v.shift[1] ≈ area.width.value / 2 + stl.FIT * min(area.width.value, area.height.value) * v.zoom
  # Two clicks put it back in the middle
  move!(w, v)
  click!(w, v)
  click!(w, v)
  @test v.shift == (0.0, 0.0)
end

# A material can have a picture that's wrapped round the model. This square
# faces the front. Its picture is green on the left and blue on the right, and
# each corner of the square says where in the picture it is.

"A PNG `w` pixels wide and `h` tall, with the colour that `colour(x, y)` gives each pixel as 0xAARRGGBB"
png(colour, w, h) = begin
  pixels = UInt32[colour(x, y) for y in 0:h-1 for x in 0:w-1]
  info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_BGRA_8888, Skia.SK_ALPHA_TYPE_PREMUL, w, h))
  GC.@preserve info pixels begin
    data = Skia.sk_data_new_with_copy(pointer(pixels), UInt64(4w * h))
    image = Skia.sk_image_new_raster_data(info, data, Csize_t(4w))
    encoded = Skia.sk_encode_png(C_NULL, image, Int32(6))
    out = copy(unsafe_wrap(Array, Ptr{UInt8}(Skia.sk_data_get_data(encoded)), Skia.sk_data_get_size(encoded)))
    Skia.sk_data_unref(encoded)
    Skia.sk_image_unref(image)
    Skia.sk_data_unref(data)
    out
  end
end

const halves = png((x, y) -> x < 8 ? 0xff00ff00 : 0xff0000ff, 16, 16)
const square_bytes = vcat(bytes(-1f0, -1f0, 0f0, 1f0, -1f0, 0f0, 1f0, 1f0, 0f0, -1f0, 1f0, 0f0,   # the corners, from the bottom left round to the top left
                                0f0, 1f0, 1f0, 1f0, 1f0, 0f0, 0f0, 0f0,                           # where each is in the picture, whose top is 0
                                0x00, 0x01, 0x02, 0x00, 0x02, 0x03, 0x00, 0x00), halves)

glb(joinpath(dir, "square.glb"), """
{"asset": {"version": "2.0"},
 "nodes": [{"mesh": 0}],
 "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "indices": 2, "material": 0}]}],
 "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0}}],
 "textures": [{"source": 0, "sampler": 0}],
 "samplers": [{"wrapS": 33071, "wrapT": 33071}],
 "images": [{"bufferView": 3, "mimeType": "image/png"}],
 "accessors": [{"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3"},
               {"bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"},
               {"bufferView": 2, "componentType": 5121, "count": 6, "type": "SCALAR"}],
 "bufferViews": [{"buffer": 0, "byteLength": 48}, {"buffer": 0, "byteOffset": 48, "byteLength": 32},
                 {"buffer": 0, "byteOffset": 80, "byteLength": 6}, {"buffer": 0, "byteOffset": 88, "byteLength": $(length(halves))}],
 "buffers": [{"byteLength": $(length(square_bytes))}]}
""", square_bytes)

let v = STLViewer(joinpath(dir, "square.glb"), turn=0.0, tilt=0.0), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  @test v.model isa Mesh && triangles(v.model) == 2
  look = v.model.look
  @test look.materials[2].base.image == 1 && length(look.textures) == 1
  # The picture is kept at its own size and at each half of it, down to one pixel
  @test [(l.w, l.h) for l in look.textures[1].levels] == [(16, 16), (8, 8), (4, 4), (2, 2), (1, 1)]
  p = picture(v)
  left, right = p[end÷2, end÷2-size(p, 1)÷6], p[end÷2, end÷2+size(p, 1)÷6]
  @test green(left) > 100 && green(left) > 3blue(left) && green(left) > 3red(left)
  @test blue(right) > 100 && blue(right) > 3green(right) && blue(right) > 3red(right)
end

# A big model with materials has a rougher copy too, which keeps what each triangle is made of
let around = 300, up = 150
  at(i, j) = (θ = π * j / up; φ = 2π * i / around; Vec((sin(θ) * cos(φ), sin(θ) * sin(φ), cos(θ))))
  ball = Vec[]
  for i in 0:around-1, j in 0:up-1
    push!(ball, at(i, j), at(i, j + 1), at(i + 1, j + 1), at(i, j), at(i + 1, j + 1), at(i + 1, j))
  end
  half = length(ball) ÷ 6
  gold = GLTF.Material((1f0, 0.8f0, 0.3f0), 1f0, 0.3f0, (0f0, 0f0, 0f0), GLTF.BARE, GLTF.BARE, GLTF.BARE, GLTF.BARE, 1f0, GLTF.BARE, 1f0, 0)
  m = Mesh(GLTF.Model(ball, copy(ball), NTuple{2,Float32}[], Vec[], vcat(fill(Int32(1), half), fill(Int32(2), half)), [GLTF.PLAIN, gold], Vector{UInt8}[]))
  @test triangles(m) > 80_000
  # The triangles with no area at the ball's top and bottom are gone, and so is what they were made of
  @test length(m.look.made_of) == triangles(m) && length(m.look.normals) == 3triangles(m)
  r = rough(m, 20_000)
  @test 2000 < triangles(r) <= 20_000
  @test length(r.look.made_of) == triangles(r) && length(r.look.normals) == 3triangles(r)
  @test Set(r.look.made_of) == Set(Int32[1, 2])
end

# A viewer that fills its room is as big as the window. A scroll makes its model bigger, from a mouse's wheel
# or from two fingers on a trackpad, and moves it nowhere.
let v = STLViewer(joinpath(dir, "box.glb"), fill=true), w = Window(v, size=(500px, 440px))
  frame(w)
  r = rect(v)
  @test (r.left, r.top, r.width, r.height) == (0px, 0px, 500px, 440px)
  # The model has all of that but the line under it that says what it is
  area = r.children[1]
  @test area.width == 500px && 380px < area.height < 440px
  move!(w, v)
  onscroll(w, Vec2{px}(0px, 2px), false)
  @test v.zoom > 1
  zoom = v.zoom
  onscroll(w, Vec2{px}(0px, 2px), true)
  @test v.zoom > zoom
  # A scroll across, as from the thumb wheel of a mouse, neither zooms nor moves the model
  zoom, shift = v.zoom, v.shift
  onscroll(w, Vec2{px}(3px, 0px), false)
  @test v.zoom ≈ zoom && all(isapprox.(v.shift, shift))
  holding(() -> onscroll(w, Vec2{px}(0px, 2px), false), w, (Keys.cmd,))
  @test v.zoom > zoom
  # With another key held, a scroll does nothing to the model
  zoom, shift = v.zoom, v.shift
  holding(() -> onscroll(w, Vec2{px}(3px, 2px), false), w, (Keys.opt,))
  @test (v.zoom, v.shift) == (zoom, shift)
end

# A file can give its model a sky, and a light that shines one way, like the Sun. This sky is blue above
# the level of the eye and green below it. The sky shows behind the model, in place of the studio's wall.
const sky_picture = png((x, y) -> y < 16 ? 0xff2040ff : 0xff20c040, 64, 32)
const sky_bytes = vcat(box_bytes, sky_picture)
glb(joinpath(dir, "sky.glb"), """
{"asset": {"version": "2.0"}, "extensionsUsed": ["KHR_lights_punctual"],
 "extensions": {"KHR_lights_punctual": {"lights": [{"type": "directional", "color": [1, 0.5, 0.25], "intensity": 4}]}},
 "scene": 0, "scenes": [{"nodes": [0, 1], "extras": {"sky": {"image": 0}}}],
 "nodes": [{"mesh": 0}, {"rotation": [-0.7071068, 0, 0, 0.7071068], "extensions": {"KHR_lights_punctual": {"light": 0}}}],
 "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
 "images": [{"bufferView": 2, "mimeType": "image/png"}],
 "accessors": [{"bufferView": 0, "componentType": 5126, "count": 8, "type": "VEC3"},
               {"bufferView": 1, "componentType": 5123, "count": 36, "type": "SCALAR"}],
 "bufferViews": [{"buffer": 0, "byteLength": 96}, {"buffer": 0, "byteOffset": 96, "byteLength": 72},
                 {"buffer": 0, "byteOffset": 168, "byteLength": $(length(sky_picture))}],
 "buffers": [{"byteLength": $(length(sky_bytes))}]}
""", sky_bytes)

let g = GLTF.model(joinpath(dir, "sky.glb"))
  @test g.sky == 1 && !isempty(g.pictures[1])
  # The light's node is turned to shine straight down, so the way to it is up, which is z in the viewer
  @test all(isapprox.(g.sun, (0f0, 0f0, 1f0), atol=1f-5))
  @test g.sunlight == (4f0, 2f0, 1f0)
  # A file with no sky and no light has neither
  plain = GLTF.model(joinpath(dir, "box.glb"))
  @test plain.sky == 0 && plain.sunlight == (0f0, 0f0, 0f0)
end

let v = STLViewer(joinpath(dir, "sky.glb"), tilt=0.0), w = Window(Box(width(400px), v), size=(440px, 440px))
  frame(w)
  sky = v.model.look.sky
  @test sky !== nothing && read_gltf(joinpath(dir, "box.glb")).look.sky === nothing
  # The sky is kept at smaller and smaller sizes, down to one colour, for surfaces that are rougher and rougher
  @test size.(sky.seen, 1) == [256, 128, 64, 32, 16, 8, 4, 2, 1]
  # Light falls from the blue half on a surface that faces up, and from the green half on one that faces down
  let above = stl.glimpse(sky.falls, (0f0, 0f0, 1f0)), below = stl.glimpse(sky.falls, (0f0, 0f0, -1f0))
    @test above[3] > 2above[2] && below[2] > 2below[3]
  end
  # The eye is level, so the sky behind the model is blue in the top of the view and green in the bottom
  p = picture(v)
  top, bottom = p[2, 2], p[end-1, 2]
  @test blue(top) > 200 && blue(top) > 2green(top)
  @test green(bottom) > 150 && green(bottom) > 2blue(bottom)
  # The sky turns as the model turns: from high above, all of it that shows is below the level of the eye
  v.tilt = 60.0
  frame(w)
  @test green(picture(v)[2, 2]) > 2blue(picture(v)[2, 2])
  v.tilt = 0.0
  frame(w)
  @test picture(v)[2, 2] == top
  # The sky is far away, so it doesn't grow as the model grows
  move!(w, v)
  holding(() -> onscroll(w, Vec2{px}(0px, 2px)), w, (Keys.cmd,))
  v.moved = 0.0
  frame(w)
  @test v.zoom > 1 && picture(v)[2, 2] == top
end

# A model that code makes has no file. The viewer takes the bytes of a .glb file, and a newer model the same way.
let sky = read(joinpath(dir, "sky.glb")), box = read(joinpath(dir, "box.glb"))
  @test GLTF.model(box).points == GLTF.model(joinpath(dir, "box.glb")).points
  v = STLViewer(path="made.jl", turn=10.0)
  w = Window(Box(width(400px), v), size=(440px, 440px))
  @test show!(v, sky) === v && v.model isa Mesh
  frame(w)
  first = v.model
  v.turn, v.zoom = 75.0, 2.0
  # A newer model takes its place, and stays turned as it was. A picture that both have is read once, and so is the sky.
  show!(v, sky)
  @test v.model !== first && v.model.look.textures[1] === first.look.textures[1] && v.model.look.sky === first.look.sky
  @test (v.turn, v.zoom) == (75.0, 2.0)
  frame(w)
  # A model with no sky stands in the studio again
  show!(v, box)
  @test v.model isa Mesh && v.model.look.sky === nothing && triangles(v.model) == 24
  frame(w)
  # Bytes that hold no model give a sentence, which the viewer shows
  show!(v, UInt8[1, 2, 3])
  @test v.model isa String
  frame(w)
end

# With no line under it, the model is all that the viewer shows
let v = STLViewer(joinpath(dir, "box.glb")), w = Window(v, size=(440px, 440px))
  frame(w)
  with_foot = rect(v).height
  @test length(rect(v).children) == 2
  v.foot = false
  frame(w)
  # Its line is 1px wide, above the model and below it
  @test length(rect(v).children) == 1 && rect(v).height == v.height + 2px < with_foot
end

# A sheet 70 wide, and 24 strips that cover it, 0.002 nearer the eye. Seen close, each of the sheet's two triangles
# is far wider than the view. Only the strips show: the sums that say which surface is nearer are exact enough.
let strips = 24, wide = 70f0 / 24
  quad(x0, x1, y) = Vec[(x0, y, -3.8f0), (x1, y, -3.8f0), (x1, y, 3.8f0), (x0, y, -3.8f0), (x1, y, 3.8f0), (x0, y, 3.8f0)]
  m = Mesh(vcat(quad(-35f0, 35f0, 0f0), (quad(-35f0 + (k - 1) * wide, -35f0 + k * wide, -0.002f0) for k in 1:strips)...))
  @test triangles(m) == 2 + 2strips
  w, h = 2200, 1200
  which, depth, pixels = zeros(Int32, w * h), zeros(Float32, w * h), zeros(UInt32, w * h)
  for (turn, zoom) in ((35.0, 16.0), (35.0, 60.0))
    focal = Float32(stl.FIT * h * zoom) * sqrt(stl.EYE^2 - 1)
    stl.see!(which, depth, w, h, m, stl.sight(turn, 22.0), focal, w / 2f0, h / 2f0)
    @test count(>(2), which) > w * h ÷ 4 && count(t -> t == 1 || t == 2, which) == 0
    # A model with no materials is drawn by `render!`. Its picture is the same with the sheet as without it.
    colour = Vec((0.5f0, 0.6f0, 0.8f0))
    stl.render!(pixels, depth, w, h, Mesh(m.corners[7:end], m.normals[3:end], m.size), stl.sight(turn, 22.0), focal, w / 2f0, h / 2f0, colour)
    alone = copy(depth)
    stl.render!(pixels, depth, w, h, m, stl.sight(turn, 22.0), focal, w / 2f0, h / 2f0, colour)
    @test count(>(0f0), depth) > w * h ÷ 4 && depth == alone
  end
end
