# Sound and video, played by macOS. AVFoundation is the part of macOS that
# plays a file, and it plays what QuickTime plays: MP3, M4A, WAV, AIFF and FLAC
# sound, and MP4 and MOV video. This file only works on macOS. Check
# `Sys.isapple()` before you use it.
#
#     p = Playback("song.mp3")
#     play!(p)
#     position(p), duration(p)   # in seconds
#     seek!(p, 30)
#     pause!(p)
#
# macOS reads the file while the app's event loop runs, so a `Playback` is
# `ready` a moment after it's made, and only in an app with a window open.

@use "./objc" libobjc cls sel msg nsstring jstring with_pool
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
end

Playback(path::AbstractString) = begin
  # The classes of AVFoundation only have their names once it's loaded
  Base.Libc.Libdl.dlopen(AVFoundation)
  player = with_pool() do
    url = msg(cls("NSURL"), "fileURLWithPath:", nsstring(abspath(path)))
    msg(msg(cls("AVPlayer"), "alloc"), "initWithURL:", url)
  end
  finalizer(close!, Playback(abspath(path), player, msg(player, "currentItem"), C_NULL, 0, 0.0, 0.0, 0))
end

"Stop it and give its memory back to macOS"
close!(p::Playback) = begin
  p.player == C_NULL && return
  sounding[] === p && (sounding[] = nothing)
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

"How long the file is, in seconds. It's 0 until the file is `ready`."
duration(p::Playback) = p.item == C_NULL ? 0.0 : seconds(time_of(p.item, "duration"))

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

"Play it from where it is, or from the start if it's at the end. The file that was playing stops."
play!(p::Playback) = begin
  p.player == C_NULL && return p
  other = sounding[]
  other isa Playback && other !== p && pause!(other)
  duration(p) > 0 && position(p) >= duration(p) - 0.05 && seek!(p, 0)
  sounding[] = p
  p.missed = 0
  msg(p.player, "play")
  guard!()
  p
end

pause!(p::Playback) = (p.player == C_NULL || msg(p.player, "pause"); p)

"Stop the file that plays now, if one does"
silence!() = (p = sounding[]; p isa Playback && pause!(p); nothing)

"Go to `s` seconds from the start of the file"
seek!(p::Playback, s) = begin
  p.player == C_NULL && return p
  # The two zeros ask for that time exactly. Without them macOS goes to a time near it that's quicker to find.
  ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, CMTime, CMTime, CMTime), p.player,
        sel("seekToTime:toleranceBefore:toleranceAfter:"), cmtime(clamp(s, 0.0, max(duration(p), 0.0))), cmtime(0), cmtime(0))
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

"Note that a player shows `p` now"
shown!(p::Playback) = (p.seen = time(); p)

const timer = Ref{Object}(C_NULL)

look(::Object, ::Object)::Cvoid = begin
  try
    p = sounding[]
    if !(p isa Playback) || !playing(p)
      sounding[] = nothing
      ccall((:CFRunLoopTimerInvalidate, CoreFoundation), Cvoid, (Object,), timer[])
      ccall((:CFRelease, CoreFoundation), Cvoid, (Object,), timer[])
      timer[] = C_NULL
    elseif p.seen > 0   # a file that no player ever showed plays on: a script may have started it
      p.seen == p.checked ? (p.missed += 1) : (p.missed = 0; p.checked = p.seen)
      p.missed >= 2 && pause!(p)
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
    wants = msg(cls("NSMutableDictionary"), "dictionary")
    set(key, value) = ccall((:objc_msgSend, libobjc), Cvoid, (Object, Object, Object, Object), wants, sel("setObject:forKey:"),
                            value, constant(CoreVideo, key))
    set(:kCVPixelBufferPixelFormatTypeKey, number(0x42475241))   # the letters BGRA: the order of the bytes of a pixel, as Skia has them
    if width > 0 && height > 0
      set(:kCVPixelBufferWidthKey, number(width))
      set(:kCVPixelBufferHeightKey, number(height))
    end
    p.output = msg(msg(cls("AVPlayerItemVideoOutput"), "alloc"), "initWithPixelBufferAttributes:", wants)
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

export Playback, ready, failed, duration, playing, play!, pause!, seek!, volume!, picture_size, watch!, watching, picture, shown!, close!, silence!,
       sounding, Levels, finished, progress, level
