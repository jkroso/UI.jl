@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "github.com/jkroso/Font.jl/units" px
@use "../abstract" SemanticUI describe carry!
@use "../Geometric"...
@use "../draw" frame rect
@use "../testing"...
@use "../media" Recording start! stop! recording elapsed loudness microphone ready duration
@use "./Recorder" AudioRecorder record! stop! toggle! parts plays
@use "./Player" AudioPlayer

if Sys.isapple()

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

middle(r) = (r.left + r.width / 2, r.top + r.height / 2)

@def mutable struct Shelf <: SemanticUI end
describe(s::Shelf) = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(10px), child_gap=10px, Alignment.Start, s.children...)

const dir = mktempdir()

# A recorder of a file that isn't there yet has a button and a row of bars, and it isn't recording
let a = AudioRecorder(joinpath(dir, "new.m4a"))
  w = Window(Shelf(a), size=(500px, 200px))
  frame(w)
  @test !recording(a) && !plays(a)
  button, bars = parts(a)
  @test button.width ≈ button.height && bars.width > 300px
end

# A recorder of a file that's there plays it
let sound = joinpath(dir, "tone.wav")
  open(sound, "w") do io
    rate, n = 8000, 8000
    write(io, "RIFF", UInt32(36 + 2n), "WAVE", "fmt ", UInt32(16), UInt16(1), UInt16(1), UInt32(rate), UInt32(2rate), UInt16(2), UInt16(16),
          "data", UInt32(2n))
    write(io, [round(Int16, 16384 * sin(2pi * 220 * i / rate)) for i in 0:n-1])
  end
  a = AudioRecorder(sound)
  w = Window(Shelf(a), size=(500px, 200px))
  frame(w)
  @test plays(a) && a.player isa AudioPlayer && parts(a) === nothing
  @test until(() -> (frame(w); ready(a.player.media)))
  @test duration(a.player.media) ≈ 1 atol=0.01
end

# A recorder that's made again in place of one that records goes on with its recording
let old = AudioRecorder(joinpath(dir, "a.m4a")), new = AudioRecorder(joinpath(dir, "a.m4a")), other = AudioRecorder(joinpath(dir, "b.m4a"))
  old.recording, old.heard = Recording(old.path), [0.5]
  carry!(new, old)
  @test new.recording === old.recording && new.heard == [0.5]
  carry!(other, old)
  @test other.recording === nothing
end

# Recording from the microphone. It records the room, so it only runs when it's asked for: UI_TEST_MICROPHONE=1
if get(ENV, "UI_TEST_MICROPHONE", "") == "1" && microphone() == :yes
  let r = Recording(joinpath(dir, "mic.m4a"))
    @test start!(r) && recording(r)
    loop(0.5)
    @test 0.3 < elapsed(r) < 1 && 0 <= loudness(r) <= 1
    stop!(r)
    @test !recording(r) && filesize(r.path) > 0
    took = elapsed(r)
    @test took > 0.3 && elapsed(r) == took   # it keeps how long it took
  end
  # A click on the button records, and a second click stops. Then the recorder plays what it recorded.
  let a = AudioRecorder(joinpath(dir, "clicked.m4a"))
    w = Window(Shelf(a), size=(500px, 200px))
    frame(w)
    click!(w, middle(parts(a)[1]))
    @test recording(a)
    for _ in 1:10
      frame(w)
      loop(0.05)
    end
    @test length(a.heard) >= 3
    click!(w, middle(parts(a)[1]))
    @test !recording(a)
    frame(w)
    @test plays(a)
    @test until(() -> (frame(w); ready(a.player.media)))
    @test duration(a.player.media) > 0.3
  end
end

end
