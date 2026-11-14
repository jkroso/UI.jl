@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"... text_width
@use "../abstract" SemanticUI WrapMode describe focus theme scale handled sized carry!
@use "../draw" draw cursor redraw_in! rect
@use "../media" Recording start! stop! recording elapsed loudness microphone ask_microphone! can_ask
@use "./Icon" Icon
@use "./Player" AudioPlayer card clock within BAR GAP pause! toggle!
@use Colors: RGB, @colorant_str

# A recorder records sound from the microphone into a file:
#
#     AudioRecorder("memo.m4a")
#
# Click its red button to start, and click it again to stop. While it records,
# bars show how loud the sound was, the newest at the right, and a clock shows
# how long it has recorded. Once it stops, the recorder is a player for the
# file. If the file is there already, the recorder is a player from the start.
#
# macOS asks once whether the app may use the microphone. The recorder waits
# while macOS asks, and starts when the answer is yes. macOS records the sound,
# so the recorder only works on a Mac. A recording goes on until it's stopped
# or the app quits, even while the app doesn't show the recorder.

const RED = RGB(0.92, 0.26, 0.24)   # the button that records is this colour in any theme
const STEP = 0.1                    # how many seconds of sound each bar shows

@def mutable struct AudioRecorder <: SemanticUI
  path::String = ""
  # What it remembers between frames
  recording::Any = nothing              # the Recording, once it has started
  heard::Vector{Float64} = Float64[]    # how loud each STEP seconds of the recording was, from 0 to 1
  waiting::Bool = false                 # for macOS to say whether the app may use the microphone
  problem::String = ""                  # why it couldn't record. It shows in place of the bars.
  player::Any = nothing                 # the AudioPlayer of the file, once there's a file to play
end

"`AudioRecorder(\"memo.m4a\")` records into that file. A path that isn't absolute starts from the folder that Julia is in now."
AudioRecorder(path::AbstractString; kwargs...) = AudioRecorder(; path=abspath(path), kwargs...)

"Is it recording now?"
recording(a::AudioRecorder) = a.recording isa Recording && recording(a.recording)

"How many seconds it has recorded"
elapsed(a::AudioRecorder) = a.recording isa Recording ? elapsed(a.recording) : 0.0

"""
Start to record, in place of what's in the file. If macOS hasn't asked yet
whether the app may use the microphone, it asks now, and the recorder starts
when the answer is yes.
"""
record!(a::AudioRecorder) = begin
  recording(a) && return a
  a.problem = ""
  Sys.isapple() || (a.problem = "Sound records on a Mac only"; return a)
  allowed = microphone()
  if allowed == :ask
    # A program that runs in a terminal can't ask, and macOS would stop it if it tried
    if can_ask()
      ask_microphone!()
      a.waiting = true
    else
      a.problem = "macOS can't ask to use the microphone from a terminal. Allow the terminal in System Settings."
    end
    return a
  end
  a.waiting = false
  allowed == :no && (a.problem = "This app may not use the microphone. Allow it in System Settings › Privacy & Security."; return a)
  # The player had the old file open
  a.player === nothing || (pause!(a.player); a.player = nothing)
  r = Recording(a.path)
  start!(r) || (a.problem = "macOS couldn't record into $(basename(a.path))"; return a)
  a.recording = r
  empty!(a.heard)
  a
end

"Stop recording. From then on, the recorder plays the file."
stop!(a::AudioRecorder) = begin
  a.waiting = false
  a.recording isa Recording && stop!(a.recording)
  a
end

"Record if it isn't, and stop if it is"
toggle!(a::AudioRecorder) = recording(a) || a.waiting ? stop!(a) : record!(a)

"Note how loud the microphone is, once for each STEP seconds since it was last noted"
hear!(a::AudioRecorder) = begin
  recording(a) || return
  n = floor(Int, elapsed(a) / STEP)
  length(a.heard) < n || return
  level = loudness(a.recording)
  while length(a.heard) < n
    push!(a.heard, level)
  end
end

"Does it play the file now, in place of recording?"
plays(a::AudioRecorder) = !recording(a) && !a.waiting && isfile(a.path) && filesize(a.path) > 0

describe(a::AudioRecorder) = begin
  t, k = theme(a), scale(theme(a))
  # Once macOS answers, the recorder starts, or says why it can't
  a.waiting && (microphone() == :ask ? redraw_in!(a, 0.25) : record!(a))
  if plays(a)
    if a.player === nothing
      a.player = AudioPlayer(path=a.path)
      setfield!(a.player, :parent, a)
    end
    return Column(width(grow=GrowType.Grow), a.player)
  end
  # The clock and the bars move on while it records
  recording(a) && (hear!(a); redraw_in!(a, STEP))
  words(s) = Text(s, size=sized(12pt, t), color=t.dim)
  middle = a.waiting ? words("Waiting for you to let this app use the microphone") :
           isempty(a.problem) ? Box(width(grow=GrowType.Grow), height(32px * k)) :   # the bars are drawn here
           words(a.problem)
  time = Text(clock(elapsed(a)), size=sized(12pt, t), color=t.dim, wrap=WrapMode.none, align=TextAlign.Right)
  Row(card(t)..., height(56px * k), padding(12px * k, 0px), child_gap=12px * k,
    Box(width(32px * k), height(32px * k), radius(16px * k), background(a.waiting ? t.track : RED),
      Icon(recording(a) ? "stop-fill" : "record-fill", size=18px * k, color=colorant"white")),
    middle,
    # Room for the time, so that the bars keep their length while it changes
    Row(width(text_width(time, replace(clock(max(elapsed(a), 60)), r"\d" => "0"))), time))
end

"Where a frame put the button and the bars, or nothing if it shows a player or words in place of the bars"
parts(a::AudioRecorder) = begin
  r = rect(a)
  (r === nothing || plays(a) || a.waiting || !isempty(a.problem) || length(r.children) != 3) && return nothing
  (r.children[1], r.children[2])
end

draw(ctx, size, ui::ConcreteRect, a::AudioRecorder) = begin
  found = parts(a)
  found === nothing && return
  _, area = found
  t, k = theme(a), scale(theme(a))
  step = (BAR + GAP) * k
  n = max(1, floor(Int, Float64(area.width / step)))
  # The newest bars, from the left. Once they reach the right, the older ones go off the left.
  shown = a.heard[max(1, end - n + 1):end]
  for i in 1:n
    # A loud sound is as tall as the track, and silence is a dot, as it is before the recording starts
    tall = max(BAR * k, area.height * (i <= length(shown) ? shown[i] : 0.0))
    rounded_rectangle(ctx, area.left + step * (i - 1), area.top + (area.height - tall) / 2, BAR * k, tall, BAR * k / 2,
                      background=i <= length(shown) ? RED : t.track)
  end
end

cursor(::AudioRecorder) = :hand

# A click on the button records, and a second click stops
onkey(a::AudioRecorder, e::KeyPress{Keys.mouse_left}) = begin
  focus(a)
  r = rect(a)
  (r !== nothing && !plays(a) && !isempty(r.children) && within(r.children[1], e.window.mouse, 4px)) && toggle!(a)
  handled
end

onkey(a::AudioRecorder, ::KeyPress{Keys.space}) = (plays(a) || toggle!(a); handled)

# A recorder made again in place of this one, as a live block makes it when its code runs again, records on
carry!(new::AudioRecorder, old::AudioRecorder) = begin
  new.path == old.path || return new
  new.recording, new.heard, new.waiting = old.recording, old.heard, old.waiting
  new
end

export AudioRecorder, record!, stop!, toggle!
