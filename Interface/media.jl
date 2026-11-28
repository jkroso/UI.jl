# Sound and video, played by macOS. AVFoundation is the part of macOS that
# plays a file, and it plays what QuickTime plays: MP3, M4A, WAV, AIFF and FLAC
# sound, and MP4 and MOV video. This file only works on macOS. Check
# `Sys.isapple()` before you use it.
#
#     p = Playback("song.mp3")
#     play!(p)
#     position(p), duration(p)   # in seconds
#     seek!(p, 30)
#     speed!(p, 1.5)             # half as fast again, with each voice at its own pitch
#     pause!(p)
#
# `Playback("walk.mov", from=61, to=86)` plays only that part of the file: from
# 61 seconds after its start to 86. It starts at 61, and it stops at 86 as it
# would at the end of the file.
#
# `Playback("http://127.0.0.1:8123/film/index.m3u8", length=5830)` plays what
# that web address gives, which can be a stream that's still being made. macOS
# can't say how long such a stream is until its last piece is written, so
# `length` says it, in seconds.
#
# `Playback("cat.mp4", loop=true, muted=true, autoplay=true)` plays as a GIF
# does in a web page. `autoplay` plays it as soon as macOS can. `loop` starts
# it again from the start each time it gets to the end. `muted` plays it with
# no sound, and then it doesn't count as the one file that plays: any number of
# muted files play at once, beside the one with sound.
#
# macOS reads the file while the app's event loop runs, so a `Playback` is
# `ready` a moment after it's made, and only in an app with a window open.

@use "./objc" libobjc cls sel msg send get_value nsstring jstring with_pool
@use Skia

const AVFoundation = "/System/Library/Frameworks/AVFoundation.framework/AVFoundation"
const CoreMedia = "/System/Library/Frameworks/CoreMedia.framework/CoreMedia"
const CoreVideo = "/System/Library/Frameworks/CoreVideo.framework/CoreVideo"
const CoreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
const AudioToolbox = "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox"

const Object = Ptr{Cvoid}

"A time in a file, the way macOS counts it: `value ÷ timescale` seconds"
struct CMTime
  value::Int64
  timescale::Int32
  flags::UInt32
  epoch::Int64
end

"A CMTime in seconds. A time that macOS doesn't know yet is 0."
seconds(t::CMTime) = (s = ccall((:CMTimeGetSeconds, CoreMedia), Float64, (CMTime,), t); isfinite(s) ? s : 0.0)
cmtime(s) = ccall((:CMTimeMakeWithSeconds, CoreMedia), CMTime, (Float64, Int32), s, 600)
time_of(obj, name) = ccall((:objc_msgSend, libobjc), CMTime, (Object, Object), obj, sel(name))

"The object that a macOS library keeps under the name `name`, like the key of a setting"
constant(lib, name) = unsafe_load(Ptr{Object}(Base.Libc.Libdl.dlsym(Base.Libc.Libdl.dlopen(lib), name)))

"A sound or a video file that macOS plays"
mutable struct Playback
  path::String
  player::Object    # macOS's AVPlayer
  item::Object      # the file in the player
  output::Object    # gives the pictures of a video, or C_NULL before `watch!`
  turn::Int         # how far each picture must turn to be upright, in degrees clockwise
  seen::Float64     # when a player last showed it, or 0 if none has
  checked::Float64  # what `seen` was, the last time the timer looked
  missed::Int       # how many times in a row the timer found `seen` as it was
  from::Float64     # the part of the file that plays, in seconds from its start. `to` is Inf for the end of the file.
  to::Float64
  placed::Bool      # has it gone to `from`? It goes there once the file is ready.
  speed::Float64    # how fast it plays: 1 is as fast as the file was made, and 2 is twice as fast
  long::Float64     # how long it is in seconds, as the one who made it said, for when macOS can't say. 0 when nobody said.
  wanted::Float64   # the time that `seek!` asked for and macOS can't go to yet, in a stream that's still being made. NaN when there's none.
  loop::Bool        # it starts again at the start of the part that plays, each time it gets to the end
  muted::Bool       # it makes no sound, and plays beside the file that does
  autoplay::Bool    # it plays as soon as it's `ready`. It's false once it has started.
  away::Bool        # it's muted, and it stopped because no player showed it. It plays on when one shows it again.
end

"True when `path` is a web address and not the path of a file"
isweb(path) = occursin(r"^https?://"i, path)

"`path` as a Playback keeps it: a web address as it is, and the path of a file from the top of the disk"
place_of(path) = isweb(path) ? String(path) : abspath(path)

Playback(path::AbstractString; from::Real=0.0, to::Real=Inf, length::Real=0.0, loop::Bool=false, muted::Bool=false, autoplay::Bool=false) = begin
  # The classes of AVFoundation only have their names once it's loaded
  Base.Libc.Libdl.dlopen(AVFoundation)
  player = with_pool() do
    url = isweb(path) ? msg(cls("NSURL"), "URLWithString:", nsstring(String(path))) :
                        msg(cls("NSURL"), "fileURLWithPath:", nsstring(abspath(path)))
    msg(msg(cls("AVPlayer"), "alloc"), "initWithURL:", url)
  end
  item = msg(player, "currentItem")
  # macOS stops at `to`, as if the file ended there
  isfinite(to) && ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, CMTime), item, sel("setForwardPlaybackEndTime:"), cmtime(to))
  muted && ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Bool), player, sel("setMuted:"), true)
  # A file that loops doesn't stop at its end, so `place!` sees it there with its speed still on, and takes it back to the start
  loop && ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Int), player, sel("setActionAtItemEnd:"), 2)   # AVPlayerActionAtItemEndNone
  from = max(Float64(from), 0.0)
  finalizer(close!, Playback(place_of(path), player, item, C_NULL, 0, 0.0, 0.0, 0, from, Float64(to), from == 0, 1.0, max(Float64(length), 0.0), NaN,
                             loop, muted, autoplay, false))
end

"Stop it and give its memory back to macOS"
close!(p::Playback) = begin
  p.player == C_NULL && return
  sounding[] === p && (sounding[] = nothing)
  filter!(q -> q !== p, quiet)
  msg(p.player, "pause")
  p.output == C_NULL || msg(p.output, "release")
  msg(p.player, "release")
  p.player = p.item = p.output = C_NULL
  nothing
end

# macOS says 0 while it reads the start of the file, then 1 if it can play it and 2 if it can't
status(p::Playback) = p.item == C_NULL ? 2 : ccall((:objc_msgSend, libobjc), Int, (Object, Object), p.item, sel("status"))

"Has macOS read enough of the file to play it?"
ready(p::Playback) = status(p) == 1
"Is it a file that macOS can't play?"
failed(p::Playback) = status(p) == 2

"""
How long the file is, in seconds. It's 0 until the file is `ready`. macOS
can't say how long a stream is while the stream is still being made, so such
a Playback gives the `length` that it was made with.
"""
duration(p::Playback) = begin
  p.item == C_NULL && return 0.0
  long = seconds(time_of(p.item, "duration"))
  long > 0 ? long : ready(p) ? p.long : 0.0
end

"""
The part of the file that plays: where it starts and where it stops, in seconds
from the start of the file. It's all of the file unless the Playback was made
for part of it. Both are 0 until the file is `ready`.
"""
span(p::Playback) = begin
  long = duration(p)
  from = clamp(p.from, 0.0, long)
  (from, clamp(p.to, from, long))
end

"How far through the file it is, in seconds"
Base.position(p::Playback) = p.player == C_NULL ? 0.0 : clamp(seconds(time_of(p.player, "currentTime")), 0.0, max(duration(p), 0.0))

"Is it playing now? It stops by itself at the end of the file."
playing(p::Playback) =
  p.player != C_NULL && ccall((:objc_msgSend, libobjc), Float32, (Object, Object), p.player, sel("rate")) != 0

"How wide and how tall the pictures of a video are, in pixels. A sound file is `(0, 0)`, and so is a video that isn't `ready`."
picture_size(p::Playback) =
  p.item == C_NULL ? (0.0, 0.0) : ccall((:objc_msgSend, libobjc), NTuple{2,Float64}, (Object, Object), p.item, sel("presentationSize"))

# One file plays at a time, as in a music app. This is the one that plays now.
const sounding = Ref{Any}(nothing)
# The muted files that play now. They make no sound, so they play beside it, as many as the app shows.
const quiet = Playback[]

"""
Play it from where it is. If it's at the end of the part that plays, or outside
that part, it plays from the start of the part. The file that was playing stops,
unless one of the two is muted.
"""
play!(p::Playback) = begin
  p.player == C_NULL && return p
  if p.muted
    any(q -> q === p, quiet) || push!(quiet, p)
  else
    other = sounding[]
    other isa Playback && other !== p && pause!(other)
    sounding[] = p
  end
  from, to = span(p)
  to > 0 && !(from - 0.05 <= position(p) < to - 0.05) && seek!(p, from)
  p.away = p.autoplay = false
  p.missed = 0
  rate!(p, p.speed)
  guard!()
  p
end

pause!(p::Playback) = (p.away = false; p.player == C_NULL || msg(p.player, "pause"); p)

"Tell macOS to play at `r` times as fast as the file was made. 0 stops it."
rate!(p::Playback, r) = ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Float32), p.player, sel("setRate:"), Float32(r))

"""
Play at `s` times as fast as the file was made: 2 is twice as fast, and 0.5 is
half as fast. A file that plays changes speed at once. One that's stopped plays
at that speed when it plays again. macOS keeps each voice at its own pitch.
"""
speed!(p::Playback, s::Real) = begin
  s > 0 || error("A file plays at a speed above 0. $s isn't one.")
  p.speed = Float64(s)
  playing(p) && rate!(p, p.speed)
  p
end

"Stop the file that plays now, if one does"
silence!() = (p = sounding[]; p isa Playback && pause!(p); nothing)

"A part of a file, the way macOS counts it: where it starts and how long it is"
struct CMTimeRange
  start::CMTime
  duration::CMTime
end

"""
How far into the file macOS can go now, in seconds from its start. For a file
that's all of it. A stream that's still being made has a list of its pieces,
which macOS reads again every few seconds, and macOS goes only as far as the
list went when it last read it.
"""
reach(p::Playback) = begin
  p.item == C_NULL && return 0.0
  with_pool() do
    ranges = msg(p.item, "seekableTimeRanges")
    n = ccall((:objc_msgSend, libobjc), Int, (Object, Object), ranges, sel("count"))
    n == 0 && return 0.0
    last = ccall((:objc_msgSend, libobjc), Object, (Object, Object, Int), ranges, sel("objectAtIndex:"), n - 1)
    r = ccall((:objc_msgSend, libobjc), CMTimeRange, (Object, Object), last, sel("CMTimeRangeValue"))
    seconds(r.start) + seconds(r.duration)
  end
end

"The time that `seek!` asked for and macOS can't go to yet, or nothing. See `seek!`."
wanted(p::Playback) = isnan(p.wanted) ? nothing : p.wanted

"""
Go to `s` seconds from the start of the file. macOS can't go to a part of a
stream that it doesn't know of yet. Such a time is kept as `wanted`, and
`place!` goes there once macOS knows that far.
"""
seek!(p::Playback, s) = begin
  p.player == C_NULL && return p
  p.placed = true   # `place!` mustn't take it back to `from` now
  s = clamp(s, 0.0, max(duration(p), 0.0))
  p.wanted = isweb(p.path) && s > max(reach(p), position(p)) + 0.5 ? s : NaN
  isnan(p.wanted) || return p
  # The two zeros ask for that time exactly. Without them macOS goes to a time near it that's quicker to find.
  ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, CMTime, CMTime, CMTime), p.player,
        sel("seekToTime:toleranceBefore:toleranceAfter:"), cmtime(s), cmtime(0), cmtime(0))
  p
end

"""
Go to the start of the part that plays, the first time that it's called after
the file is `ready`. A player calls it in each frame. macOS can't go to a time
in a file that it hasn't read, so a Playback can't do this when it's made. It
also goes to the time that `seek!` kept as `wanted`, once macOS knows that far.
It plays a file that has `autoplay` once it's ready, and takes a file that
loops back to its start when it gets to its end.
"""
place!(p::Playback) = begin
  ready(p) || return p
  p.placed || seek!(p, p.from)
  # A time in a stream that macOS didn't know of when it was asked for
  isnan(p.wanted) || reach(p) + 0.5 < p.wanted || seek!(p, p.wanted)
  p.autoplay && play!(p)
  if p.loop && playing(p)
    from, to = span(p)
    to > from && position(p) >= to - 0.01 && seek!(p, from)
  end
  p
end

"How loud it plays: 1 is the file as it is, and 0 is silent"
volume!(p::Playback, v) = begin
  p.player == C_NULL || ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Float32), p.player, sel("setVolume:"), Float32(v))
  p
end

# --- a sound stops when its player goes ---------------------------------------------
#
# A player calls `shown!` each time it's described, which is in each frame
# while the app shows it. If the app takes the player away, there'd be no
# button left to stop the sound with. So while a file plays, a timer looks
# twice a second. When it finds that the player wasn't described since the look
# before last, it stops the file. It waits for two looks because one slow frame
# can take longer than half a second.
#
# A muted file stops in the same way, so that a video nobody sees costs nothing.
# It plays on when a player shows it again, as a GIF in a web page does. A file
# with sound waits for a click: it would be a surprise to hear it start.

"Note that a player shows `p` now. A muted file that stopped because no player showed it plays on."
shown!(p::Playback) = begin
  p.seen = time()
  p.away && play!(p)
  p
end

const timer = Ref{Object}(C_NULL)

"Stop `p` if no player showed it since the look before last. A file that no player ever showed plays on: a script may have started it."
missed!(p::Playback) = begin
  p.seen > 0 || return
  p.seen == p.checked ? (p.missed += 1) : (p.missed = 0; p.checked = p.seen)
  p.missed >= 2 || return
  pause!(p)
  p.away = p.muted
  nothing
end

look(::Object, ::Object)::Cvoid = begin
  try
    p = sounding[]
    p isa Playback && playing(p) ? missed!(p) : (sounding[] = nothing)
    foreach(missed!, quiet)
    filter!(playing, quiet)
    if sounding[] === nothing && isempty(quiet)
      ccall((:CFRunLoopTimerInvalidate, CoreFoundation), Cvoid, (Object,), timer[])
      ccall((:CFRelease, CoreFoundation), Cvoid, (Object,), timer[])
      timer[] = C_NULL
    end
  catch
  end
  nothing
end

"Start the timer, if it isn't running"
guard!() = begin
  timer[] == C_NULL || return
  now = ccall((:CFAbsoluteTimeGetCurrent, CoreFoundation), Float64, ())
  timer[] = ccall((:CFRunLoopTimerCreate, CoreFoundation), Object, (Object, Float64, Float64, UInt, Int, Ptr{Cvoid}, Object),
                  C_NULL, now + 0.5, 0.5, 0, 0, @cfunction(look, Cvoid, (Object, Object)), C_NULL)
  ccall((:CFRunLoopAddTimer, CoreFoundation), Cvoid, (Object, Object, Object),
        ccall((:CFRunLoopGetMain, CoreFoundation), Object, ()), timer[], constant(CoreFoundation, :kCFRunLoopCommonModes))
  nothing
end

# --- the pictures of a video ---------------------------------------------------------

number(n::Integer) = ccall((:objc_msgSend, libobjc), Object, (Object, Object, Int), cls("NSNumber"), sel("numberWithInteger:"), n)

"""
How far the video says its pictures must turn to be upright, in degrees
clockwise: 0, 90, 180 or 270. A phone that's held upright records its pictures
on their side, and the file says to turn them.
"""
turned(p::Playback) = begin
  tracks = msg(p.item, "tracks")
  count = ccall((:objc_msgSend, libobjc), UInt, (Object, Object), tracks, sel("count"))
  for i in 0:Int(count)-1
    track = msg(ccall((:objc_msgSend, libobjc), Object, (Object, Object, UInt), tracks, sel("objectAtIndex:"), i), "assetTrack")
    (track == C_NULL || jstring(msg(track, "mediaType")) != "vide") && continue
    # The first two of the six numbers are the cosine and the sine of the turn
    a, b = ccall((:objc_msgSend, libobjc), NTuple{6,Float64}, (Object, Object), track, sel("preferredTransform"))
    return mod(90round(Int, atand(b, a) / 90), 360)
  end
  0
end

"Is it giving the pictures of a video? It is after `watch!`."
watching(p::Playback) = p.output != C_NULL

"""
Start to get the pictures of a video. Call it once the video is `ready`.
`width` and `height` are the size to show the video at, in pixels. A video
that's bigger than that gives pictures of that size, which cost less to copy
for each frame. Give 0 for both to get pictures of the size that the file has.
"""
watch!(p::Playback, width::Integer=0, height::Integer=0) = begin
  (p.item == C_NULL || p.output != C_NULL) && return p
  with_pool() do
    p.turn = turned(p)
    # The pictures come as the file has them, before they're turned
    p.turn in (90, 270) && ((width, height) = (height, width))
    put(dict, key, value) = ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Object, Object), dict, sel("setObject:forKey:"), value, key)
    wants = msg(cls("NSMutableDictionary"), "dictionary")
    set(key, value) = put(wants, constant(CoreVideo, key), value)
    set(:kCVPixelBufferPixelFormatTypeKey, number(0x42475241))   # the letters BGRA: the order of the bytes of a pixel, as Skia has them
    if width > 0 && height > 0
      set(:kCVPixelBufferWidthKey, number(width))
      set(:kCVPixelBufferHeightKey, number(height))
    end
    # macOS converts each picture to sRGB, the colours that the window shows, as it does for a video that it
    # shows itself. Without this the pictures have the video's own numbers. For an HD video those are a little
    # darker than in QuickTime or Safari: #F38020 came out as (239,128,30), where macOS shows (241,139,33).
    av(name) = constant(AVFoundation, name)
    colours = msg(cls("NSMutableDictionary"), "dictionary")
    put(colours, av(:AVVideoColorPrimariesKey), av(:AVVideoColorPrimaries_ITU_R_709_2))   # sRGB has the primaries of HD video
    put(colours, av(:AVVideoTransferFunctionKey), av(:AVVideoTransferFunction_IEC_sRGB))
    put(colours, av(:AVVideoYCbCrMatrixKey), av(:AVVideoYCbCrMatrix_ITU_R_709_2))
    put(wants, av(:AVVideoColorPropertiesKey), colours)
    p.output = msg(msg(cls("AVPlayerItemVideoOutput"), "alloc"), "initWithOutputSettings:", wants)
    msg(p.item, "addOutput:", p.output)
  end
  p
end

"""
The picture of the video at the time it's at now, as a Skia image that's the
caller's to unref. It's C_NULL when the picture is still the one given last, and
before `watch!`. Draw it turned by `p.turn` degrees.
"""
picture(p::Playback) = begin
  p.output == C_NULL && return Ptr{Skia.sk_image_t}(C_NULL)
  now = time_of(p.player, "currentTime")
  ccall((:objc_msgSend, libobjc), Bool, (Object, Object, CMTime), p.output, sel("hasNewPixelBufferForItemTime:"), now) ||
    return Ptr{Skia.sk_image_t}(C_NULL)
  pixels = ccall((:objc_msgSend, libobjc), Object, (Object, Object, CMTime, Object), p.output,
                 sel("copyPixelBufferForItemTime:itemTimeForDisplay:"), now, C_NULL)
  pixels == C_NULL && return Ptr{Skia.sk_image_t}(C_NULL)
  # 1 says that the pixels are only read, not changed
  ccall((:CVPixelBufferLockBaseAddress, CoreVideo), Cint, (Object, UInt64), pixels, 1)
  try
    w = Int(ccall((:CVPixelBufferGetWidth, CoreVideo), Csize_t, (Object,), pixels))
    h = Int(ccall((:CVPixelBufferGetHeight, CoreVideo), Csize_t, (Object,), pixels))
    # A row can have spare bytes after its pixels
    row = ccall((:CVPixelBufferGetBytesPerRow, CoreVideo), Csize_t, (Object,), pixels)
    start = ccall((:CVPixelBufferGetBaseAddress, CoreVideo), Ptr{Cvoid}, (Object,), pixels)
    info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_BGRA_8888, Skia.SK_ALPHA_TYPE_OPAQUE, w, h))
    GC.@preserve info begin
      data = Skia.sk_data_new_with_copy(start, UInt64(row * h))
      image = Skia.sk_image_new_raster_data(info, data, row)
      Skia.sk_data_unref(data)
      image
    end
  finally
    ccall((:CVPixelBufferUnlockBaseAddress, CoreVideo), Cint, (Object, UInt64), pixels, 1)
    ccall((:CVPixelBufferRelease, CoreVideo), Cvoid, (Object,), pixels)
  end
end

# --- how loud each part of a sound file is --------------------------------------------
#
# A player draws a sound file as a row of bars, a tall bar where the sound is
# loud. To know how tall, the whole file has to be read, and an hour of sound
# takes a second or two. So the file is read a little in each frame, and the
# bars show from the left as it goes.

# How macOS says what form sound is in. The names are in the order that macOS has them.
struct SoundForm
  rate::Float64          # samples in a second
  kind::UInt32
  flags::UInt32
  packet_bytes::UInt32
  packet_frames::UInt32
  frame_bytes::UInt32
  channels::UInt32       # 2 for stereo
  bits::UInt32           # in a sample
  spare::UInt32
end

# Where macOS puts the samples that it reads
struct SoundBuffer
  buffers::UInt32
  spare::UInt32
  channels::UInt32
  bytes::UInt32
  data::Ptr{Cvoid}
end

"The number that macOS knows a four-letter name by"
code(name) = reduce((n, c) -> n << 8 | UInt32(c), collect(name), init=UInt32(0))

const CHUNK = 16384   # frames read at a time. A frame is one sample for each channel.

"""
How loud each of `parts` equal lengths of a sound file is. `read!` reads some
more of the file, and `level` is how loud a length of it is.
"""
mutable struct Levels
  file::Object              # macOS's reader, or C_NULL once the file is all read or if it can't be read
  frames::Int               # in the whole file
  channels::Int
  at::Int                   # frames read so far
  squares::Vector{Float64}  # the sum of each sample squared, for each part
  counts::Vector{Int}       # how many samples that's the sum of
  samples::Vector{Float32}
end

Levels(path::AbstractString, parts::Integer=600) = begin
  l = finalizer(close!, Levels(C_NULL, 0, 1, 0, zeros(parts), zeros(Int, parts), Float32[]))
  file = Ref{Object}(C_NULL)
  opened = with_pool() do
    url = msg(cls("NSURL"), "fileURLWithPath:", nsstring(abspath(path)))
    ccall((:ExtAudioFileOpenURL, AudioToolbox), Int32, (Object, Ref{Object}), url, file)
  end
  opened == 0 || return l
  l.file = file[]
  form, size = Ref{SoundForm}(), Ref{UInt32}(sizeof(SoundForm))
  got = ccall((:ExtAudioFileGetProperty, AudioToolbox), Int32, (Object, UInt32, Ref{UInt32}, Ptr{Cvoid}), l.file, code("ffmt"), size, form)
  frames, size = Ref{Int64}(0), Ref{UInt32}(sizeof(Int64))
  got == 0 && (got = ccall((:ExtAudioFileGetProperty, AudioToolbox), Int32, (Object, UInt32, Ref{UInt32}, Ptr{Cvoid}), l.file, code("#frm"), size, frames))
  (got == 0 && form[].channels > 0 && frames[] > 0) || return close!(l)
  l.frames, l.channels = frames[], form[].channels
  # Ask for the samples as numbers from -1 to 1, whatever form the file keeps them in. 9 says that they're Float32s with no gaps.
  wanted = Ref(SoundForm(form[].rate, code("lpcm"), 9, 4l.channels, 1, 4l.channels, l.channels, 32, 0))
  set = ccall((:ExtAudioFileSetProperty, AudioToolbox), Int32, (Object, UInt32, UInt32, Ptr{Cvoid}), l.file, code("cfmt"), sizeof(SoundForm), wanted)
  set == 0 || return close!(l)
  l.samples = Vector{Float32}(undef, CHUNK * l.channels)
  l
end

close!(l::Levels) = begin
  l.file == C_NULL || ccall((:ExtAudioFileDispose, AudioToolbox), Int32, (Object,), l.file)
  l.file = C_NULL
  l
end

"Is the file all read, or as much of it as can be?"
finished(l::Levels) = l.file == C_NULL

"Read more of the file for about `budget` seconds. It's true when the file is all read."
Base.read!(l::Levels, budget=0.006) = begin
  stop = time() + budget
  samples, n = l.samples, length(l.squares)
  while l.file != C_NULL
    frames = Ref{UInt32}(CHUNK)
    to = Ref(SoundBuffer(1, 0, l.channels, sizeof(samples), pointer(samples)))
    err = GC.@preserve samples ccall((:ExtAudioFileRead, AudioToolbox), Int32, (Object, Ref{UInt32}, Ptr{Cvoid}), l.file, frames, to)
    got = Int(frames[])
    (err != 0 || got == 0) && return (close!(l); true)
    @inbounds for frame in 0:got-1
      # macOS only guesses how long some files are, so a file can go on after the last part
      part = min(n, 1 + (l.at + frame) * n ÷ l.frames)
      for channel in 1:l.channels
        l.squares[part] += abs2(samples[frame * l.channels + channel])
      end
      l.counts[part] += l.channels
    end
    l.at += got
    time() >= stop && break
  end
  finished(l)
end

"How much of the file is read: 0 for none of it and 1 for all of it"
progress(l::Levels) = finished(l) ? 1.0 : l.frames > 0 ? min(1.0, l.at / l.frames) : 0.0

"""
How loud the file is between `from` and `to`, which are fractions of its length
from 0 to 1. It's the root of the mean of its samples squared: 0 is silence,
and a file as loud as a file can be is near 1. A part that isn't read yet is 0.
"""
level(l::Levels, from, to) = begin
  n = length(l.squares)
  a = clamp(floor(Int, from * n) + 1, 1, n)
  b = clamp(ceil(Int, to * n), a, n)
  count = sum(view(l.counts, a:b))
  count == 0 ? 0.0 : sqrt(sum(view(l.squares, a:b)) / count)
end

# --- recording from the microphone ------------------------------------------------------
#
#     r = Recording("memo.m4a")
#     start!(r)               # false if macOS can't record
#     elapsed(r), loudness(r)
#     stop!(r)                # the file can be played once it's stopped
#
# macOS records the sound as AAC in an M4A file, as Voice Memos does. It asks
# the person once whether the app may use the microphone, and `microphone()`
# says what they said. A recording goes on until it's stopped, or until the app
# quits, whatever the app shows.

"May the app use the microphone? `:yes`, `:no`, or `:ask` when macOS hasn't asked the person yet."
microphone() = begin
  Base.Libc.Libdl.dlopen(AVFoundation)
  s = ccall((:objc_msgSend, libobjc), Int, (Object, Object, Object), cls("AVCaptureDevice"), sel("authorizationStatusForMediaType:"),
            constant(AVFoundation, :AVMediaTypeAudio))
  s == 3 ? :yes : s == 0 ? :ask : :no
end

"""
Can macOS ask the person whether the app may use the microphone? It can when the
app's Info.plist gives a reason. A program that runs in a terminal has none, and
macOS stops a program that asks without one.
"""
can_ask() = with_pool() do
  info = msg(msg(cls("NSBundle"), "mainBundle"), "infoDictionary")
  info != C_NULL && msg(info, "objectForKey:", nsstring("NSMicrophoneUsageDescription")) != C_NULL
end

# macOS gives the answer to a block, the kind of function that Objective-C passes
# around. This block is global: it has no variables of its own, so macOS uses it
# where it is. `microphone()` reads the answer, so the block does nothing.
answered(::Ptr{Cvoid}, ::Bool)::Cvoid = nothing
const block = Ref{Tuple{Ptr{Cvoid},Int32,Int32,Ptr{Cvoid},Ptr{Cvoid}}}()
const block_size = Ref((UInt(0), UInt(32)))   # what's known of the block: nothing reserved, and its size in bytes

"Ask the person whether the app may use the microphone, unless macOS has asked already. `microphone()` says when they answer."
ask_microphone!() = begin
  (microphone() == :ask && can_ask()) || return
  global_block = Base.Libc.Libdl.dlsym(Base.Libc.Libdl.dlopen("/usr/lib/libSystem.B.dylib"), :_NSConcreteGlobalBlock)
  block[] = (global_block, Int32(1 << 28), Int32(0), @cfunction(answered, Cvoid, (Ptr{Cvoid}, Bool)), Base.unsafe_convert(Ptr{Cvoid}, block_size))
  ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Object, Object), cls("AVCaptureDevice"),
        sel("requestAccessForMediaType:completionHandler:"), constant(AVFoundation, :AVMediaTypeAudio), Base.unsafe_convert(Ptr{Cvoid}, block))
  nothing
end

"Sound from the microphone, recorded into a file"
mutable struct Recording
  path::String
  recorder::Object   # macOS's AVAudioRecorder while it records, or C_NULL
  took::Float64      # how many seconds it recorded, once it's stopped
end

Recording(path::AbstractString) = Recording(abspath(path), C_NULL, 0.0)

# The recordings that are going now, so that they stop when the app quits. A file that isn't stopped can't be played.
const recording_now = Recording[]
const hooked = Ref(false)   # is the code that stops them set to run when the app quits?

"Start to record into the file, in place of what's in it. It's false if macOS can't record."
start!(r::Recording) = begin
  r.recorder == C_NULL || return true
  Base.Libc.Libdl.dlopen(AVFoundation)
  mkpath(dirname(r.path))
  r.recorder = with_pool() do
    settings = msg(cls("NSMutableDictionary"), "dictionary")
    set(key, value) = ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Object, Object), settings, sel("setObject:forKey:"),
                            value, constant(AVFoundation, key))
    set(:AVFormatIDKey, number(code("aac ")))
    set(:AVSampleRateKey, number(44100))
    set(:AVNumberOfChannelsKey, number(1))   # a microphone hears one sound
    set(:AVEncoderAudioQualityKey, number(0x60))   # high
    url = msg(cls("NSURL"), "fileURLWithPath:", nsstring(r.path))
    ccall((:objc_msgSend, libobjc), Object, (Object, Object, Object, Object, Ptr{Cvoid}), msg(cls("AVAudioRecorder"), "alloc"),
          sel("initWithURL:settings:error:"), url, settings, C_NULL)
  end
  r.recorder == C_NULL && return false
  send(r.recorder, "setMeteringEnabled:", true)
  if !(get_value(Bool, r.recorder, "prepareToRecord") && get_value(Bool, r.recorder, "record"))
    msg(r.recorder, "release")
    r.recorder = C_NULL
    return false
  end
  hooked[] || (atexit(() -> foreach(stop!, copy(recording_now))); hooked[] = true)
  push!(recording_now, r)
  r.took = 0.0
  true
end

"Stop recording. The file is whole once it's stopped."
stop!(r::Recording) = begin
  r.recorder == C_NULL && return r
  r.took = get_value(Float64, r.recorder, "currentTime")
  msg(r.recorder, "stop")
  msg(r.recorder, "release")
  r.recorder = C_NULL
  filter!(x -> x !== r, recording_now)
  r
end

"Is it recording now?"
recording(r::Recording) = r.recorder != C_NULL

"How many seconds it has recorded"
elapsed(r::Recording) = recording(r) ? get_value(Float64, r.recorder, "currentTime") : r.took

"""
How loud the microphone is now, from 0 for silence to 1 for as loud as it can be.
macOS gives it in decibels, and the 50 decibels under the loudest are spread
evenly from 0 to 1, as the meters of a sound app have them.
"""
loudness(r::Recording) = begin
  recording(r) || return 0.0
  msg(r.recorder, "updateMeters")
  db = ccall((:objc_msgSend, libobjc), Float32, (Object, Object, UInt), r.recorder, sel("averagePowerForChannel:"), 0)
  clamp((db + 50) / 50, 0.0, 1.0)
end

export Playback, ready, failed, duration, span, playing, play!, pause!, seek!, place!, volume!, speed!, picture_size, watch!, watching, picture, shown!, close!, silence!,
       sounding, Levels, finished, progress, level, Recording, start!, stop!, recording, elapsed, loudness, microphone, ask_microphone!, can_ask
