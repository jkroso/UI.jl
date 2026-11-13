# Helpers for testing an app without opening its window. Make a `Window` for the
# app, don't `open` it, and send it input the way a user would:
#
#     w = Window(describe(todos), size=(440px, 520px))
#     frame(w)                                  # lay it out and draw it once
#     click!(w, app.composer.input)             # click the middle of a node
#     type!(w, "Buy milk"); press!(w, Keys.enter)
#     @test length(integrate(app)) == 1
#
# The input goes through the same handlers as the real mouse and keyboard, and
# each helper draws a frame afterwards, so what's under the mouse is up to date.

@use "github.com/jkroso/MiniFB.jl" Window AbstractWindow KeyPress KeyRelease MouseMove Typed Keys onkey onmouse ontype
@use "github.com/jkroso/Font.jl/units" px
@use "./abstract" SemanticUI same semantic_parent
@use "./draw" frame rect scene popups draw hittest
@use "./save" save_png
@use "./image" decode_image
@use GeometryBasics: Vec2
@use Skia

"The middle of a place to click: a node, a rectangle from `rect` or `(x, y)` in px"
point(w, node::SemanticUI) = begin
  r = rect(node)
  r === nothing && error("$(typeof(node)) wasn't in the window's last frame, so it has no place to click")
  Vec2{px}(r.left + r.width / 2, r.top + r.height / 2)
end
point(w, (x, y)) = Vec2{px}(x isa px ? x : px(x), y isa px ? y : px(y))

"Move the mouse to a node's middle, or to `(x, y)`"
move!(w::AbstractWindow, target) = begin
  pos = point(w, target)
  onmouse(w, MouseMove(pos, w))
  w.mouse = pos
  frame(w)
  pos
end

"Hold the keys in `mods` while `f` runs"
holding(f, w::AbstractWindow, mods) = begin
  foreach(m -> w.keys |= m, mods)
  try
    f()
  finally
    foreach(m -> w.keys ⊻= m, mods)
  end
end

"""
Click a node's middle, or `(x, y)`: move there, then press and release
`button`. Give the keys to hold meanwhile after it: `click!(w, row, Keys.cmd)`.
"""
click!(w::AbstractWindow, target, mods...; button=Keys.mouse_left) = begin
  pos = move!(w, target)
  target isa SemanticUI && reachable(w, target, pos)
  holding(w, mods) do
    w.keys |= button
    onkey(w, KeyPress{button}(0, w))
    w.keys ⊻= button
    onkey(w, KeyRelease{button}(0, w))
  end
  frame(w)
  nothing
end

"""
Check that a click at `pos` would go to `node` or to something in it. A node
that's scrolled out of view, or under a popup, can't be clicked by a user, so a
test that tries to is stopped here.
"""
reachable(w::AbstractWindow, node::SemanticUI, pos) = begin
  hit = hittest(w, pos)
  under = hit
  while under !== nothing
    same(under, node) && return true
    under = semantic_parent(under)
  end
  error("A click on the middle of $(nameof(typeof(node))) would go to $(hit === nothing ? "nothing" : nameof(typeof(hit))). " *
        "It's covered, or scrolled out of view.")
end

"Press and release `key`, while holding the keys after it: `press!(w, Keys.s, Keys.cmd)`"
press!(w::AbstractWindow, key, mods...) = begin
  holding(w, mods) do
    onkey(w, KeyPress{key}(0, w))
    onkey(w, KeyRelease{key}(0, w))
  end
  frame(w)
  nothing
end

"Type `text`, a character at a time, into the node that has the keyboard"
type!(w::AbstractWindow, text::AbstractString) = begin
  foreach(char -> ontype(w, Typed(char, w)), text)
  frame(w)
  nothing
end

"The pixels of a PNG or JPEG file, one `UInt32` each as 0xAARRGGBB, in a matrix with a row for each row of the picture"
pixels(path::AbstractString) = begin
  image = decode_image(read(path), path)
  buffer = zeros(UInt32, image.width * image.height)
  info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_BGRA_8888, Skia.sk_alpha_type_t(1), image.width, image.height))
  ok = GC.@preserve info buffer Skia.sk_image_read_pixels(image.raw, pointer_from_objref(info), pointer(buffer), Csize_t(image.width * 4),
                                                         Cint(0), Cint(0), Skia.sk_image_caching_hint_t(0))
  Skia.sk_image_unref(image.raw)
  ok || error("Skia could not read the pixels of $path")
  permutedims(reshape(buffer, image.width, image.height))
end

"""
How much two pictures differ: the fraction of their pixels where a colour
channel is more than `tolerance` (out of 255) apart. Pictures of different
sizes differ completely.
"""
difference(a::AbstractMatrix{UInt32}, b::AbstractMatrix{UInt32}; tolerance=8) = begin
  size(a) == size(b) || return 1.0
  apart(x, y) = any(shift -> abs(Int((x >> shift) & 0xff) - Int((y >> shift) & 0xff)) > tolerance, (0, 8, 16, 24))
  count(i -> apart(a[i], b[i]), eachindex(a)) / length(a)
end

export move!, click!, press!, type!, holding, pixels, difference, save_png
