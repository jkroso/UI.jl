@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "github.com/jkroso/Font.jl/units" px
@use "../abstract" SemanticUI describe
@use "../Geometric"...
@use "../draw" frame rect
@use "../testing"...
@use "../media" Playback Levels ready failed duration playing volume! picture_size finished progress level sounding silence!
@use "./Player" AudioPlayer VideoPlayer clock parts toggle! pause!

# A length of time, as a player shows it
@test clock(0) == "0:00"
@test clock(187.9) == "3:07"
@test clock(3787) == "1:03:07"

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
  end
end

end
