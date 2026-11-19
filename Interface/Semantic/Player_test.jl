@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "github.com/jkroso/Font.jl/units" px
@use "../abstract" SemanticUI describe
@use "../Geometric"...
@use "../draw" frame rect
@use "../testing"...
@use "../media" Playback Levels ready failed duration span playing volume! picture_size finished progress level sounding silence!
@use "../objc" libobjc sel
@use "../media" => Media
@use Skia
@use "./Player" AudioPlayer VideoPlayer clock parts toggle! pause! speed speed! next_speed stepped speed_label

# A length of time, as a player shows it
@test clock(0) == "0:00"
@test clock(187.9) == "3:07"
@test clock(3787) == "1:03:07"

# A click on the speed button goes from 1× to 1.5×, 2×, 0.5× and back to 1×. A speed that < or > gave goes to the next one up.
@test next_speed(1) == 1.5 && next_speed(1.5) == 2 && next_speed(2) == 0.5 && next_speed(0.5) == 1
@test next_speed(0.75) == 1 && next_speed(1.25) == 1.5 && next_speed(1.75) == 2
# < and > go a quarter at a time, and stop at 0.5× and 2×
@test stepped(1, 1) == 1.25 && stepped(1, -1) == 0.75
@test stepped(2, 1) == 2 && stepped(0.5, -1) == 0.5
# The circle shows a part of 1 as a fraction, so that each speed fits in it
@test speed_label(1.0) == "1×" && speed_label(2.0) == "2×"
@test speed_label(0.5) == "½×" && speed_label(0.75) == "¾×" && speed_label(1.25) == "1¼×" && speed_label(1.5) == "1½×" && speed_label(1.75) == "1¾×"
@test speed_label(1.3) == "1.3×"

# A player takes a web address as well as the path of a file. The address stays as it's written.
@test Media.isweb("http://127.0.0.1:8700/a/index.m3u8") && Media.isweb("HTTPS://example.com/a.mp4")
@test !Media.isweb("/tmp/a.mp4") && !Media.isweb("httpd.mp4")
@test Media.place_of("http://127.0.0.1:8700/a/index.m3u8") == "http://127.0.0.1:8700/a/index.m3u8"
@test Media.place_of("a.mp4") == abspath("a.mp4")
let v = VideoPlayer("http://127.0.0.1:8700/a/index.m3u8", length=90)
  @test v.path == "http://127.0.0.1:8700/a/index.m3u8" && v.length == 90
end

# The rest needs macOS to read and play the files
if Sys.isapple()

"Write a WAV file `seconds` long: a tone in its first half and silence in its second"
tone(path, seconds) = open(path, "w") do io
  rate = 8000
  n = rate * seconds
  write(io, "RIFF", UInt32(36 + 2n), "WAVE", "fmt ", UInt32(16), UInt16(1), UInt16(1), UInt32(rate), UInt32(2rate), UInt16(2), UInt16(16),
        "data", UInt32(2n))
  write(io, [i < n ÷ 2 ? round(Int16, 16384 * sin(2pi * 220 * i / rate)) : Int16(0) for i in 0:n-1])
end

# macOS reads a file, and its timers run, while the app's event loop runs. A test
# has no window open, so it runs the loop itself for a moment at a time.
const CoreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
loop(seconds) = ccall((:CFRunLoopRunInMode, CoreFoundation), Int32, (Ptr{Cvoid}, Float64, UInt8),
                      unsafe_load(cglobal((:kCFRunLoopDefaultMode, CoreFoundation), Ptr{Cvoid})), seconds, 0)

"Run the loop until `f()` is true, for 5 seconds at the most. It's true if `f()` came true."
until(f) = begin
  stop = time() + 5
  while !f() && time() < stop
    loop(0.02)
  end
  f()
end

"The middle of a rectangle that a frame laid out"
middle(r) = (r.left + r.width / 2, r.top + r.height / 2)

"How fast macOS plays the file now. It's 0 while the file is stopped."
rate(m::Playback) = ccall((:objc_msgSend, libobjc), Float32, (Ptr{Cvoid}, Ptr{Cvoid}), m.player, sel("rate"))

const dir = mktempdir()
const sound = joinpath(dir, "tone.wav")
tone(sound, 6)
write(joinpath(dir, "notes.wav"), "This isn't sound")

# --- how loud each part of a file is ---------------------------------------------

let l = Levels(sound, 10)
  @test !finished(l) && progress(l) == 0
  while !read!(l) end
  @test finished(l) && progress(l) == 1
  # A tone that goes half way to as loud as a file can be: the root of the mean of its squares is 0.5 ÷ √2
  @test level(l, 0, 0.5) ≈ 0.5 / sqrt(2) atol=0.01
  @test level(l, 0.5, 1) == 0
end

# A file that isn't sound has no levels to read
let l = Levels(joinpath(dir, "notes.wav"))
  @test finished(l) && level(l, 0, 1) == 0
end

# --- the players in a window ---------------------------------------------------------

@def mutable struct Shelf <: SemanticUI end
describe(s::Shelf) = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(10px), child_gap=10px, Alignment.Start, s.children...)

let a = AudioPlayer(sound), other = AudioPlayer(sound), bad = AudioPlayer(joinpath(dir, "notes.wav")), only_sound = VideoPlayer(sound)
  w = Window(Shelf(a, other, bad, only_sound), size=(500px, 400px))
  shown() = (frame(w); true)
  @test until(() -> shown() && ready(a.media) && ready(other.media) && failed(bad.media) && ready(only_sound.media))
  frame(w)
  @test duration(a.media) ≈ 6 atol=0.01
  @test finished(a.levels)
  # A file that can't be played shows a sentence in place of its button and its track
  @test parts(bad) === nothing
  # A video file with sound and no pictures has a button and a track, and no picture
  @test parts(only_sound)[4] === nothing && picture_size(only_sound.media) == (0, 0)

  foreach(p -> volume!(p.media, 0), (a, other, only_sound))   # a test makes no noise
  button, track, _, _ = parts(a)
  # A click on the button plays the file, and a second click stops it
  click!(w, middle(button))
  @test playing(a.media) && sounding[] === a.media
  click!(w, middle(button))
  @test !playing(a.media)
  # A click on the middle of the track goes to the middle of the file
  click!(w, middle(track))
  @test until(() -> shown() && abs(position(a.media) - 3) < 0.1)
  # The click gave the player the keyboard: the space bar plays and stops, and ← goes back 5 seconds, or to the start
  press!(w, Keys.space)
  @test playing(a.media)
  press!(w, Keys.space)
  @test !playing(a.media)
  press!(w, Keys.left)
  @test until(() -> shown() && position(a.media) < 0.05)

  # The speed button is a circle that hangs off the bottom edge of the player, inside its right edge
  _, bars, body, _, speeds = parts(a)
  long = bars.width
  @test speeds.width == speeds.height && speeds.top < body.top + body.height < speeds.top + speeds.height
  @test bars.left + bars.width < speeds.left && speeds.left + speeds.width < body.left + body.width
  # The player takes room for the part under its edge
  @test rect(a).top + rect(a).height ≈ speeds.top + speeds.height
  # The circle shows while the mouse is over the player. It hides when the mouse leaves, and the player keeps its room.
  shows() = !isempty(parts(a)[5].children)
  @test shows()
  tall = rect(a).height
  move!(w, (495px, 395px))
  @test !shows() && rect(a).height == tall
  # While the file plays, the circle shows wherever the mouse is
  toggle!(a); frame(w)
  @test shows()
  pause!(a); frame(w)
  @test !shows()
  # A file plays at 1× until the circle is clicked, and then at 1.5×, 2×, 0.5× and 1× again
  @test speed(a) == 1
  for s in (1.5, 2.0, 0.5, 1.0)
    click!(w, middle(speeds))
    @test speed(a) == s
  end
  # A click on the half of the circle that's under the edge works too
  click!(w, (speeds.left + speeds.width / 2, speeds.top + speeds.height - 3px))
  @test speed(a) == 1.5
  speed!(a, 1)
  # A file that plays changes speed at once
  press!(w, Keys.space)
  @test playing(a.media) && rate(a.media) == 1
  click!(w, middle(speeds))
  @test speed(a) == 1.5 && rate(a.media) == 1.5
  # It plays at that speed again after a stop
  press!(w, Keys.space)
  @test !playing(a.media)
  press!(w, Keys.space)
  @test rate(a.media) == 1.5
  pause!(a)
  # < and > go a quarter slower and faster, and stop at 0.5× and 2×. Other characters do nothing.
  type!(w, ">")
  @test speed(a) == 1.75
  type!(w, ">>>")
  @test speed(a) == 2
  type!(w, "<<<<<<<<")
  @test speed(a) == 0.5
  type!(w, "a.,")
  @test speed(a) == 0.5
  # The track is as long at each speed
  type!(w, ">")
  @test speed(a) == 0.75 && parts(a)[2].width == long
  speed!(a, 1)
  @test speed(a) == 1

  # One file plays at a time
  toggle!(a)
  toggle!(other)
  @test playing(other.media) && !playing(a.media)
  silence!()
  @test !playing(other.media)

  # A file plays on while each frame shows its player
  toggle!(a)
  for _ in 1:40
    frame(w)
    loop(0.03)
  end
  @test playing(a.media)
  # With no frame for a second and a half, the timer stops it
  loop(1.6)
  @test !playing(a.media)
  # And it plays on from there
  at = position(a.media)
  toggle!(a)
  @test until(() -> shown() && position(a.media) > at + 0.05)
  pause!(a)
  @test !playing(a.media)

  # A file stops by itself at its end, and then it plays from its start
  toggle!(other)
  press!(w, Keys.right); press!(w, Keys.right)   # the keyboard is still `a`'s, so this leaves `other` alone
  click!(w, middle(parts(other)[2]) .+ (parts(other)[2].width * 0.48, 0px))
  @test until(() -> shown() && !playing(other.media))
  @test position(other.media) ≈ 6 atol=0.05
  toggle!(other)
  @test until(() -> shown() && playing(other.media) && 0.05 < position(other.media) < 2)
  pause!(other)
end

# --- video ----------------------------------------------------------------------------
#
# ffmpeg makes the test's videos: a picture 160 wide and 90 tall, and the same
# video with a note that says to turn it on its side, as a phone's video has.

if Sys.which("ffmpeg") !== nothing
  flat, turned = joinpath(dir, "flat.mp4"), joinpath(dir, "turned.mp4")
  run(pipeline(`ffmpeg -loglevel error -y -f lavfi -i testsrc=duration=2:size=160x90:rate=10 -pix_fmt yuv420p $flat`, devnull))
  run(pipeline(`ffmpeg -loglevel error -y -display_rotation 90 -i $flat -c copy $turned`, devnull))
  let v = VideoPlayer(flat, height=180px), t = VideoPlayer(turned, height=180px)
    w = Window(Shelf(v, t), size=(500px, 600px))
    shown() = (frame(w); true)
    # Each player gets its first picture once the file is read
    @test until(() -> shown() && v.still.image != C_NULL && t.still.image != C_NULL)
    @test picture_size(v.media) == (160, 90) && v.media.turn == 0
    # macOS says how big the turned video shows, and the player turns each picture to match
    @test picture_size(t.media) == (90, 160) && t.media.turn in (90, 270)
    button, track, strip, picture = parts(v)
    # The player is as wide as a picture 180px tall, and its border takes a little of that
    @test rect(v).width ≈ 320px && 178px < picture.height <= 180px
    # A click on the picture plays the video, and a second click stops it
    click!(w, middle(picture))
    @test playing(v.media)
    @test until(() -> shown() && position(v.media) > 0.2)
    click!(w, middle(picture))
    @test !playing(v.media)
    # A click near the end of the track goes there
    click!(w, (track.left + track.width * 0.75, track.top + track.height / 2))
    @test until(() -> shown() && abs(position(v.media) - 1.5) < 0.1)
    # A video's speed button hangs off the bottom edge of its controls too, and < and > change its speed
    speeds = parts(v)[5]
    @test speeds.top < strip.top + strip.height < speeds.top + speeds.height && speeds.left + speeds.width < strip.left + strip.width
    click!(w, middle(speeds))
    @test speed(v) == 1.5
    type!(w, "<")
    @test speed(v) == 1.25
    # The other video plays at its own speed
    @test speed(t) == 1
    speed!(v, 1)
    # The turned video is tall and narrow. The speed button hangs under its controls, so its track keeps its length.
    @test rect(t).width ≈ 240px && parts(t)[2].width > 40px
  end

  # A player of part of a file: from 0.5 seconds to 1.2
  let v = VideoPlayer(flat, height=180px, from=0.5, to=1.2), rest = VideoPlayer(flat, height=180px, from=1.5)
    w = Window(Shelf(v, rest), size=(700px, 600px))
    shown() = (frame(w); true)
    # Its first picture is the one at the start of the part
    @test until(() -> shown() && v.still.image != C_NULL && abs(position(v.media) - 0.5) < 0.05)
    @test span(v.media) == (0.5, 1.2)
    # With no `to`, the part goes on to the end of the file
    @test until(() -> shown() && span(rest.media) == (1.5, 2.0) && abs(position(rest.media) - 1.5) < 0.05)
    button, track, strip, picture = parts(v)
    # It stops at the end of the part, as it would at the end of the file
    click!(w, middle(picture))
    @test playing(v.media)
    @test until(() -> shown() && !playing(v.media))
    @test position(v.media) ≈ 1.2 atol=0.05
    # And then it plays from the start of the part
    toggle!(v)
    @test until(() -> shown() && playing(v.media) && position(v.media) < 1.0)
    pause!(v)
    # The track is the part, so a click three quarters of the way along goes three quarters of the way through the part
    click!(w, (track.left + track.width * 0.75, track.top + track.height / 2))
    @test until(() -> shown() && abs(position(v.media) - (0.5 + 0.7 * 0.75)) < 0.05)
    # ← can't go before the part
    press!(w, Keys.left)
    @test until(() -> shown() && abs(position(v.media) - 0.5) < 0.05)
  end

  # The pictures come in sRGB, as macOS shows the video itself. An HD video of #F38020 shows as (241,139,33).
  # Its own numbers, which the pictures had before, are a little darker: about (239,128,30).
  orange = joinpath(dir, "orange.mp4")
  run(pipeline(`ffmpeg -loglevel error -y -f lavfi -i color=c=0xF38020:s=64x64:d=1:r=10
                -vf scale=out_color_matrix=bt709:out_range=tv,format=yuv420p -c:v libx264 -crf 0
                -x264-params colorprim=bt709:transfer=bt709:colormatrix=bt709:range=tv $orange`, devnull))
  let m = Playback(orange), image = Ref(Ptr{Skia.sk_image_t}(C_NULL))
    @test until(() -> ready(m))
    Media.watch!(m)
    Media.play!(m)
    # `picture` gives each picture once, and `until` asks once more after it comes, so keep the first
    @test until(() -> (image[] == C_NULL && (image[] = Media.picture(m)); image[] != C_NULL))
    if image[] != C_NULL
      info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_RGBA_8888, Skia.SK_ALPHA_TYPE_UNPREMUL, 1, 1))
      rgba = zeros(UInt8, 4)
      GC.@preserve info rgba Skia.sk_image_read_pixels(image[], pointer_from_objref(info), pointer(rgba), Csize_t(4), Cint(32), Cint(32), Skia.sk_image_caching_hint_t(0))
      @test all(abs.(Int.(rgba[1:3]) .- [241, 139, 33]) .<= 2)
      Skia.sk_image_unref(image[])
    end
    Media.close!(m)
  end
end

end
