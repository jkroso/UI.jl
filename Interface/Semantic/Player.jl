@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle sk_color
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove Typed onkey onmouse ontype flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"... text_width
@use "../abstract" SemanticUI WrapMode describe focus theme scale handled sized window_of
@use "../draw" draw cursor redraw_in! rect ishovered
@use "../fonts" skia_font
@use "../media" Playback place_of wanted ready failed duration span playing play! pause! seek! place! speed! picture_size watch! watching picture shown! Levels finished level
@use "./Icon" Icon
@use "./STLViewer" density smooth
@use Colors: RGBA, @colorant_str

# A player for a sound file, and one for a video file:
#
#     AudioPlayer("song.mp3")
#     VideoPlayer("holiday.mov")
#
# Each has a round button that plays the file and stops it. Beside the button
# is a track that shows how far through the file it is. An AudioPlayer's track
# is a row of bars, a tall bar where the sound is loud. Click the track, or
# drag along it, to go to that part of the file. A click on the picture of a
# video plays it and stops it too.
#
# A VideoPlayer can play part of a file:
#
#     VideoPlayer("walk.mov", from=61, to=86)
#
# That one starts 61 seconds into the file and stops at 86. Its track is that
# part of the file, and its times are the file's own, so it shows 1:01 / 1:26
# before it plays.
#
# A VideoPlayer can play a stream from a web address, as well as a file:
#
#     VideoPlayer("http://127.0.0.1:8123/film/index.m3u8", length=5830)
#
# `length` is how long the stream is, in seconds. macOS can't say that while
# the stream is still being made, and the track needs it.
#
# A VideoPlayer shows the words of its `caption` over the foot of its picture,
# in white with a dark edge, as a subtitle shows. The app sets `caption` as
# the video plays, since the player doesn't read subtitles itself.
#
# A VideoPlayer whose `screen` is true is made to be all that a screen shows,
# or all of a space that an app keeps for the video. Its picture is as big as
# the room it's given, with black round it and no border. Its button, its
# track and its times lie over the foot of the picture. They show while the
# video is stopped, and for a moment after the mouse moves. While the video
# plays and the mouse is still, only the picture shows. Its corners are square,
# or as round as its `corners` says.
#
# A VideoPlayer can play as a GIF does in a web page:
#
#     VideoPlayer("cat.mp4", autoplay=true, loop=true, muted=true)
#
# `autoplay` plays it as soon as macOS can. `loop` starts it again each time
# it gets to its end. `muted` plays it with no sound. A muted video doesn't stop
# the file that plays, and a file that starts doesn't stop it. When the app
# stops showing a muted video, it stops, and it plays on when the app shows it
# again.
#
# A small circle hangs off the bottom edge of each player, at the right, while
# the mouse is over the player or the file plays. It says how fast the file
# plays: 1× is as fast as it was made. Click it to play at 1½×, then at 2×, then
# at ½×, then at 1× again. macOS keeps each voice at its own pitch.
#
# Once a click has given a player the keyboard, the space bar plays and stops,
# ← and → go back and on by 5 seconds, and < and > play slower and faster, by a
# quarter at a time, from ½× to 2×.
#
# macOS plays the file, so the players only work on a Mac. One file plays at a
# time: when a player starts, the one that was playing stops. A muted video is
# the exception. When an app stops showing a player, its file stops within a
# second or two.

"The last picture of a video, kept so that a frame in which the video didn't move on draws it again"
mutable struct Still
  image::Ptr{Skia.sk_image_t}
  Still() = finalizer(release!, new(C_NULL))
end

release!(s::Still) = (s.image == C_NULL || Skia.sk_image_unref(s.image); s.image = C_NULL; nothing)

@def mutable struct AudioPlayer <: SemanticUI
  path::String = ""
  # What it remembers between frames
  media::Any = nothing     # the Playback of the file, once the player has been shown
  aim::Any = nothing       # when a click asked for a time in the file, and the time, until the file gets there
  drag::Bool = false       # is the mouse dragging along the track?
  levels::Any = nothing    # the Levels of the file: how loud each part of it is
end

@def mutable struct VideoPlayer <: SemanticUI
  path::String = ""
  height::px = 360px       # the most that the picture has. The player is as wide as a picture of that height, or as the room it's given.
  from::Float64 = 0.0      # the part of the file that it plays, in seconds from the file's start. `to` is Inf for the file's end.
  to::Float64 = Inf
  length::Float64 = 0.0    # how long a stream is in seconds, for a `path` that's a web address. macOS can't say while the stream is being made.
  caption::String = ""     # words that show over the foot of the picture, like a subtitle. Each line of it is a line there.
  screen::Bool = false     # it's all that a screen shows: black is round its picture, and its controls lie over the foot of the picture
  corners::px = 0px        # how round the corners of a player whose `screen` is true are
  autoplay::Bool = false   # it plays as soon as macOS can
  loop::Bool = false       # it starts again at its start each time it gets to its end
  muted::Bool = false      # it plays with no sound, beside the file that plays
  stirred::Float64 = 0.0   # when the mouse last moved over it. A player that fills a screen shows its controls for a moment after.
  # What it remembers between frames
  media::Any = nothing
  aim::Any = nothing
  drag::Bool = false
  still::Still = Still()   # the picture that it shows now
end

"`AudioPlayer(\"song.mp3\")` plays that file. A path that isn't absolute starts from the folder that Julia is in now."
AudioPlayer(path::AbstractString; kwargs...) = AudioPlayer(; path=abspath(path), kwargs...)
"`VideoPlayer(\"holiday.mov\")` plays that file. A path that isn't absolute starts from the folder that Julia is in now. A web address stays as it is."
VideoPlayer(path::AbstractString; kwargs...) = VideoPlayer(; path=place_of(path), kwargs...)

const Player = Union{AudioPlayer,VideoPlayer}

"The file as macOS plays it. It's opened the first time that the player is shown."
media(p::AudioPlayer) = (p.media === nothing && (p.media = Playback(p.path)); p.media::Playback)
media(p::VideoPlayer) = begin
  p.media === nothing && (p.media = Playback(p.path, from=p.from, to=p.to, length=p.length, loop=p.loop, muted=p.muted, autoplay=p.autoplay))
  p.media::Playback
end

"Has macOS read enough of the file to play it? A player that hasn't been shown yet hasn't asked macOS for its file."
ready(p::Player) = p.media !== nothing && ready(p.media)
"Is it a file that macOS can't play?"
failed(p::Player) = p.media !== nothing && failed(p.media)
"Is it playing now?"
playing(p::Player) = p.media !== nothing && playing(p.media)

"""
Has the player a picture of its video to show? It has none until macOS has read
the start of the file, and it shows black meanwhile. So an app can show a
picture of its own over it until then, like the first frame of the video.
"""
has_picture(v::VideoPlayer) = v.still.image != C_NULL

"""
How far through the file it is, in seconds. After a click on the track it's the
time that the click asked for, until the file gets there. The file takes a
moment, and the track would jump back to the old time meanwhile.
"""
at(p::Player) = begin
  # A time in a stream that macOS can't go to yet. The track shows it until the stream gets there.
  ahead = wanted(media(p))
  ahead === nothing || return ahead
  now = position(media(p))
  p.aim === nothing && return now
  asked, time_asked = p.aim
  (p.drag || (abs(now - time_asked) > 0.25 && time() - asked < 1)) && return time_asked
  p.aim = nothing
  now
end

"Stop the file where it is. `toggle!` plays it on from there."
pause!(p::Player) = (p.media === nothing || pause!(p.media); p)

"Play the file if it's stopped, and stop it if it's playing"
toggle!(p::Player) = begin
  m = media(p)
  ready(m) || return
  playing(m) ? pause!(m) : play!(m)
  nothing
end

"Go to `s` seconds from the start of the file, or to the nearest end of the part of the file that plays"
goto!(p::Player, s) = begin
  m = media(p)
  ready(m) || return
  s = clamp(s, span(m)...)
  seek!(m, s)
  p.aim = (time(), s)
  nothing
end

"How fast the file plays: 1 is as fast as it was made, and 2 is twice as fast"
speed(p::Player) = media(p).speed

"Play the file at `s` times as fast as it was made. A file that plays changes speed at once."
speed!(p::Player, s) = (speed!(media(p), s); nothing)

# The speeds that < and > step through, and the ones that a click on the speed button goes round
const SPEEDS = (0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0)
const ROUND = (0.5, 1.0, 1.5, 2.0)

"The speed after `s` when the speed button is clicked: the next one up in ROUND, or 0.5 after 2. So 1 goes to 1.5, then 2, then 0.5, and back to 1."
next_speed(s) = (i = findfirst(>(s + 0.001), ROUND); i === nothing ? ROUND[1] : ROUND[i])

"The speed in SPEEDS that's `by` steps on from `s`: 1 for faster, -1 for slower. It stops at 0.5 and at 2."
stepped(s, by) = SPEEDS[clamp(argmin([abs(x - s) for x in SPEEDS]) + by, 1, length(SPEEDS))]

const QUARTERS = Dict(0.25 => "¼", 0.5 => "½", 0.75 => "¾")

"A speed as the speed button shows it, with a fraction for a quarter, a half or three quarters: 1×, 1½× or ¾×"
speed_label(s) = begin
  n, part = floor(Int, s), s - floor(s)
  part == 0 && return "$n×"
  haskey(QUARTERS, part) || return "$(round(s, digits=2))×"
  (n == 0 ? "" : "$n") * QUARTERS[part] * "×"
end

"""
What a player does each time it's described. It notes that the app still shows
it, which keeps the file playing. It asks for the next frame too, because what
it shows changes with time: within `wait` seconds while the file plays, and
sooner while the file loads or goes to a new time.
"""
tick!(p::Player, wait) = begin
  m = place!(shown!(media(p)))
  w = window_of(p)
  # The button can come up while the mouse is somewhere else, and then no move tells the player
  p.drag && w !== nothing && !(Keys.mouse_left in w.keys) && (p.drag = false)
  if !(ready(m) || failed(m)) || p.aim !== nothing
    redraw_in!(p, 1 / 30)
  elseif wanted(m) !== nothing
    redraw_in!(p, 0.25)   # it waits for more of a stream
  elseif playing(m)
    redraw_in!(p, wait)
  end
  m
end

"A length of time as a clock shows it: 3:07, or 1:03:07 for an hour or more"
clock(seconds) = begin
  s = floor(Int, seconds)
  hours, minutes, s = s ÷ 3600, s % 3600 ÷ 60, s % 60
  hours > 0 ? "$hours:$(lpad(minutes, 2, '0')):$(lpad(s, 2, '0'))" : "$minutes:$(lpad(s, 2, '0'))"
end

"How far through the file it is and where it stops, like 0:12 / 3:40. It stops at the end of the file unless it plays part of the file."
times(p::Player, t) = begin
  stop = clock(span(media(p))[2])
  text = Text("$(clock(at(p))) / $stop", size=sized(12pt, t), color=t.dim, wrap=WrapMode.none, align=TextAlign.Right)
  # Room for its widest time, so that the track keeps its length while the time changes
  Row(width(text_width(text, replace("$stop / $stop", r"\d" => "0"))), text)
end

"The round button that plays and stops. It's grey until the file can play."
button(p::Player, t, size) = begin
  m = media(p)
  Box(width(size), height(size), radius(size / 2), background(ready(m) ? t.accent : t.track),
    Icon(playing(m) ? "pause-fill" : "play-fill", size=size * 0.56, color=t.on_accent))
end

"The words in the speed button, for the speed `s`. They're the accent colour at any speed but 1×."
speed_text(s, t) = Text(speed_label(s), size=sized(9pt, t), color=s == 1 ? t.dim : t.accent, wrap=WrapMode.none, align=TextAlign.Center)

"How big the speed button is across: room for its widest words, 1¾×"
speed_size(t) = text_width(speed_text(1.75, t), "1¾×") + 6px * scale(t)

"Does the speed button show? Only while the mouse is over the player, or while its file plays."
speed_shows(p::Player) = ishovered(p) || playing(media(p))

"""
`body`, which is what a player shows, with the speed button hanging off its
bottom edge, `inset` from its right edge. The button is a circle. A third of it
is over the body, which keeps it clear of the time above it, and the rest is
under the body. The player takes room for the part under the body too, so that
the button doesn't cover what's under the player, and a click on any part of the
button is the player's. The room is there while the button is hidden too, so
that nothing moves when it shows.
"""
hung(body, p::Player, t, inset; wide=width(grow=GrowType.Grow)) = begin
  d = speed_size(t)
  circle = speed_shows(p) ?
    Box(width(d), height(d), radius(d / 2), border(1px, :solid, t.line), background(t.surface), Alignment.Center,
        offset_y=-d / 3, speed_text(speed(p), t)) :
    Box(width(d), height(d), offset_y=-d / 3)   # empty, where the button would be
  Column(wide, body,
    Row(width(grow=GrowType.Grow), height(d * 2 / 3), padding(0px, inset, 0px, 0px), justify=Alignment.End, align=Alignment.Start, circle))
end

"The border and the background that each player has"
card(t) = (width(grow=GrowType.Grow), radius(8px), border(1px, :solid, t.line), background(t.surface))

"What a player shows for a file that macOS can't play"
unplayable(p::Player, t, kind) =
  Row(card(t)..., height(56px * scale(t)), padding(16px * scale(t), 0px),
    Text("$(basename(p.path)) isn't a $kind file that can be played", size=sized(12pt, t), color=t.dim))

const BAR, GAP = 2px, 1px   # how wide a bar of an AudioPlayer is, and the space between two bars

describe(a::AudioPlayer) = begin
  t, k = theme(a), scale(theme(a))
  Sys.isapple() || return Row(card(t)..., height(56px * k), padding(16px * k, 0px),
                              Text("Sound plays on a Mac only", size=sized(12pt, t), color=t.dim))
  m = tick!(a, pace(a))
  failed(m) && return unplayable(a, t, "sound")
  a.levels === nothing && (a.levels = Levels(a.path))
  # The file is read a little in each frame, and the bars show as it goes
  finished(a.levels) || (read!(a.levels); redraw_in!(a, 0.001))
  body = Row(card(t)..., height(56px * k), padding(12px * k, 0px), child_gap=12px * k,
    button(a, t, 32px * k),
    Box(width(grow=GrowType.Grow), height(32px * k)),   # the bars are drawn here
    times(a, t))
  hung(body, a, t, 12px * k)
end

describe(v::VideoPlayer) = begin
  t, k = theme(v), scale(theme(v))
  Sys.isapple() || return Row(card(t)..., height(56px * k), padding(16px * k, 0px),
                              Text("Video plays on a Mac only", size=sized(12pt, t), color=t.dim))
  m = tick!(v, 1 / 60)
  failed(m) && return unplayable(v, t, "video")
  w, h = picture_size(m)
  controls = Row(width(grow=GrowType.Grow), height(40px * k), padding(10px * k, 0px), child_gap=10px * k,
    button(v, t, 26px * k),
    Box(width(grow=GrowType.Grow), height(6px * k), radius(3px * k), background(t.track)),
    times(v, t))
  # A file with sound and no pictures, as an MP4 can be, shows the controls alone
  ready(m) && (w == 0 || h == 0) && return hung(Column(card(t)..., controls), v, t, 10px * k)
  if v.screen
    # The controls are only given their places here. `draw` draws them over the picture, which it draws over all of this.
    # They're bigger on a big screen
    g = k * screen_scale(v)
    f = screen_font(v)
    strip = Row(width(grow=GrowType.Grow), height(52px * g), padding(18px * g, 0px), child_gap=14px * g,
      Box(width(30px * g), height(30px * g)),
      Box(width(grow=GrowType.Grow), height(6px * g)),
      Box(width(text_width(f, replace("$(clock(span(m)[2])) / $(clock(span(m)[2]))", r"\d" => "0"))), height(30px * g)))
    return Column(width(grow=GrowType.Grow),
      Stack(width(grow=GrowType.Grow), height(v.height), radius(v.corners), background(colorant"black"),
        Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow)),   # the picture is drawn here
        Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), justify=Alignment.End, strip)),
      Row(width(grow=GrowType.Grow), height(0px), Box(width(0px), height(0px))))   # where the speed button would hang
  end
  # A tall narrow video still has room under it for the controls
  wide = max(240px * k, v.height * (w > 0 && h > 0 ? w / h : 16 / 9))
  body = Column(width(grow=GrowType.Grow), radius(8px), border(1px, :solid, t.line), background(t.surface),
    Image(width(grow=GrowType.Grow), aspect=Float64(wide / v.height)),   # the picture is drawn here
    controls)
  hung(body, v, t, 10px * k, wide=width(grow=GrowType.Grow, max=wide))
end

"""
Where a frame put the parts of a player: its button, its track, the strip that
holds them, its picture, or nothing for the picture if it has none, and its
speed button. It's nothing when the player shows a sentence in place of its parts.
"""
parts(::AudioPlayer, ui) = begin
  length(ui.children) == 2 || return nothing
  body, under = ui.children
  length(body.children) == 3 ? (body.children[1], body.children[2], body, nothing, under.children[1]) : nothing
end
parts(v::VideoPlayer, ui) = begin
  length(ui.children) == 2 || return nothing
  body, under = ui.children
  if v.screen
    # The picture, and over it a column with the controls at its foot
    (length(body.children) == 2 && length(body.children[2].children) == 1) || return nothing
    strip = body.children[2].children[1]
    (strip isa ConcreteRect && length(strip.children) == 3) || return nothing
    return (strip.children[1], strip.children[2], strip, body.children[1], under.children[1])
  end
  strip = isempty(body.children) ? nothing : body.children[end]
  (strip isa ConcreteRect && length(strip.children) == 3) || return nothing
  (strip.children[1], strip.children[2], strip, length(body.children) == 2 ? body.children[1] : nothing, under.children[1])
end
parts(p::Player) = (r = rect(p); r === nothing ? nothing : parts(p, r))

"""
Where the bottom edge of a player's card was in the last frame, or nothing if
the player wasn't drawn or shows a sentence. The speed button hangs off this
edge, so the player reaches a little lower. Put a thing under the card here.
"""
card_bottom(p::Player) = (found = parts(p); found === nothing ? nothing : found[3].top + found[3].height)

"How many bars fit in the track of an AudioPlayer that's `width` wide"
bars(a::AudioPlayer, width) = max(1, floor(Int, Float64(width / ((BAR + GAP) * scale(theme(a))))))

"""
How long an AudioPlayer waits for its next frame while it plays: until the next
bar changes colour. It's never more than a quarter of a second, so that the
time it shows keeps up. A long file needs few frames, so it costs little to play.
"""
pace(a::AudioPlayer) = begin
  found = parts(a)
  found === nothing ? 1 / 30 : clamp(duration(media(a)) / bars(a, found[2].width), 1 / 30, 0.25)
end

"How much of the part that plays has played: 0 at its start and 1 at its end"
played(p::Player) = begin
  from, to = span(media(p))
  to > from ? clamp((at(p) - from) / (to - from), 0.0, 1.0) : 0.0
end

draw(ctx, size, ui::ConcreteRect, a::AudioPlayer) = begin
  found = parts(a, ui)
  (found === nothing || a.levels === nothing) && return
  t, k = theme(a), scale(theme(a))
  area = found[2]
  step = (BAR + GAP) * k
  n = bars(a, area.width)
  loud = [level(a.levels, (i - 1) / n, i / n) for i in 1:n]
  loudest = maximum(loud)
  done = played(a)
  for i in 1:n
    # The loudest part of the file is as tall as the track, and silence is a dot
    tall = max(BAR * k, area.height * (loudest > 0 ? loud[i] / loudest : 0.0))
    rounded_rectangle(ctx, area.left + step * (i - 1), area.top + (area.height - tall) / 2, BAR * k, tall, BAR * k / 2,
                      background=(i - 0.5) / n <= done ? t.accent : t.track)
  end
end

draw(ctx, size, ui::ConcreteRect, v::VideoPlayer) = begin
  found = parts(v, ui)
  found === nothing && return
  _, track, _, area = found
  t, k = theme(v), scale(theme(v))
  m = media(v)
  area === nothing || screen(ctx, ui.children[1], area, v, m)   # the body: the speed button hangs under it
  if v.screen
    controls_show(v) || return
    # The shade behind the controls stops at the round corners of the picture
    body = ui.children[1]
    clip = Skia.sk_path_new()
    Skia.sk_path_add_rounded_rect(clip, Ref(Skia.sk_rect_t(flt(body.left), flt(body.top), flt(body.left + body.width), flt(body.top + body.height))),
                                  flt(v.corners), flt(v.corners), Skia.SK_PATH_DIRECTION_CW)
    Skia.sk_canvas_save(ctx)
    Skia.sk_canvas_clip_path_with_operation(ctx, clip, Skia.SK_CLIP_OP_INTERSECT, true)
    controls_over(ctx, v, m, found...)
    Skia.sk_canvas_restore(ctx)
    Skia.sk_path_delete(clip)
    return
  end
  # The part of the track that has played, and a knob at the end of it, as a Slider has
  full = track.width * played(v)
  full > 0px && rounded_rectangle(ctx, track.left, track.top, full, track.height, track.height / 2, background=t.accent)
  r = 6px * k
  rounded_rectangle(ctx, track.left + full - r, track.top + track.height / 2 - r, 2r, 2r, r, background=t.accent)
end

"Draw the picture of the video in `area`, as big as fits, with black beside it. A video that's stopped has a play sign over it."
screen(ctx, ui, area, v::VideoPlayer, m::Playback) = begin
  if ready(m)
    if !watching(m)
      # Ask for pictures no bigger than they're shown. A big video costs less that way.
      w, h = picture_size(m)
      room = min(area.width.value / w, area.height.value / h) * density(ctx)
      room < 0.8 ? watch!(m, 2round(Int, w * room / 2), 2round(Int, h * room / 2)) : watch!(m)
    end
    new = picture(m)
    new == C_NULL || (release!(v.still); v.still.image = new)
  end
  left, top, wide, tall = flt(area.left), flt(area.top), flt(area.width), flt(area.height)
  # The picture stops inside the player's border and its round corners
  inset, round = v.screen ? (0px, v.corners) : (1px, 7px)   # a picture that fills a screen has the corners that the player is given
  edge = Ref(Skia.sk_rect_t(flt(ui.left + inset), flt(ui.top + inset), flt(ui.left + ui.width - inset), flt(ui.top + ui.height - inset)))
  clip = Skia.sk_path_new()
  Skia.sk_path_add_rounded_rect(clip, edge, flt(round), flt(round), Skia.SK_PATH_DIRECTION_CW)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_canvas_save(ctx)
  Skia.sk_canvas_clip_path_with_operation(ctx, clip, Skia.SK_CLIP_OP_INTERSECT, true)
  Skia.sk_paint_set_color(paint, sk_color(colorant"black"))
  Skia.sk_canvas_draw_rect(ctx, Ref(Skia.sk_rect_t(left, top, left + wide, top + tall)), paint)
  image = v.still.image
  if image != C_NULL
    w, h = Float32(Skia.sk_image_get_width(image)), Float32(Skia.sk_image_get_height(image))
    # A picture that the file says to turn is drawn round the middle of the screen, turned
    sideways = m.turn in (90, 270)
    fit = sideways ? min(wide / h, tall / w) : min(wide / w, tall / h)
    Skia.sk_canvas_save(ctx)
    Skia.sk_canvas_translate(ctx, left + wide / 2, top + tall / 2)
    Skia.sk_canvas_rotate_radians(ctx, Float32(deg2rad(m.turn)))
    from = Ref(Skia.sk_rect_t(0f0, 0f0, w, h))
    to = Ref(Skia.sk_rect_t(-w * fit / 2, -h * fit / 2, w * fit / 2, h * fit / 2))
    Skia.sk_canvas_draw_image_rect(ctx, image, from, to, Ref(smooth), paint, Skia.SRC_RECT_CONSTRAINT_FAST)
    Skia.sk_canvas_restore(ctx)
  end
  # Over the controls of a player that fills a screen, while they show
  captions(ctx, v.caption, left, top, wide, v.screen && controls_show(v) ? tall - flt(40px * scale(theme(v)) * screen_scale(v)) : tall)
  if ready(m) && !playing(m)
    # A dark disc with a white triangle that points right
    cx, cy, r = left + wide / 2, top + tall / 2, flt(26px * scale(theme(v)))
    Skia.sk_paint_set_color(paint, sk_color(RGBA(0.0, 0.0, 0.0, 0.5)))
    Skia.sk_canvas_draw_circle(ctx, cx, cy, r, paint)
    sign = Skia.sk_path_new()
    Skia.sk_path_move_to(sign, cx - 0.3f0 * r, cy - 0.42f0 * r)
    Skia.sk_path_line_to(sign, cx + 0.46f0 * r, cy)
    Skia.sk_path_line_to(sign, cx - 0.3f0 * r, cy + 0.42f0 * r)
    Skia.sk_path_close(sign)
    Skia.sk_paint_set_color(paint, sk_color(colorant"white"))
    Skia.sk_canvas_draw_path(ctx, sign, paint)
    Skia.sk_path_delete(sign)
  end
  Skia.sk_canvas_restore(ctx)
  Skia.sk_paint_delete(paint)
  Skia.sk_path_delete(clip)
end

const CONTROLS_STAY = 2.5   # seconds that the controls of a player that fills a screen show for, after the mouse moves

"How much bigger the controls of a player that fills a screen are than a player's in a page: more on a taller screen"
screen_scale(v::VideoPlayer) = clamp(Float64(v.height / 720px), 1.0, 1.8)

"The font of the times of a player that fills a screen"
screen_font(v::VideoPlayer) = skia_font(theme(v).family, sized(12pt, theme(v)) * screen_scale(v))

"""
True while a VideoPlayer shows its controls. One that fills a screen shows
them while it's stopped, while its track is dragged, and for a moment after
the mouse moves. Any other shows them all the time.
"""
controls_show(v::VideoPlayer) =
  !v.screen || v.drag || time() - v.stirred < CONTROLS_STAY || v.media === nothing || !playing(v.media)

"""
Draw the controls of a player that fills a screen, over the foot of its
picture: a shade, the sign that plays or stops, the track with the part that
has played, and the times. They're white, since the picture under them is
any colour.
"""
controls_over(ctx, v::VideoPlayer, m, button, track, strip, _...) = begin
  k = scale(theme(v)) * screen_scale(v)
  white = sk_color(colorant"white")
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  # A shade behind them, a little taller than the strip
  Skia.sk_paint_set_color(paint, sk_color(RGBA(0.0, 0.0, 0.0, 0.5)))
  Skia.sk_canvas_draw_rect(ctx, Ref(Skia.sk_rect_t(flt(strip.left), flt(strip.top - 8px * k), flt(strip.left + strip.width), flt(strip.top + strip.height))), paint)
  Skia.sk_paint_set_color(paint, white)
  # Two bars while it plays, and a triangle that points right while it's stopped
  cx, cy, r = flt(button.left + button.width / 2), flt(button.top + button.height / 2), flt(button.width / 2)
  sign = Skia.sk_path_new()
  if playing(m)
    for x in (cx - 0.5f0 * r, cx + 0.12f0 * r)
      Skia.sk_path_add_rect(sign, Ref(Skia.sk_rect_t(x, cy - 0.6f0 * r, x + 0.38f0 * r, cy + 0.6f0 * r)), Skia.SK_PATH_DIRECTION_CW)
    end
  else
    Skia.sk_path_move_to(sign, cx - 0.42f0 * r, cy - 0.62f0 * r)
    Skia.sk_path_line_to(sign, cx + 0.62f0 * r, cy)
    Skia.sk_path_line_to(sign, cx - 0.42f0 * r, cy + 0.62f0 * r)
    Skia.sk_path_close(sign)
  end
  Skia.sk_canvas_draw_path(ctx, sign, paint)
  Skia.sk_path_delete(sign)
  Skia.sk_paint_delete(paint)
  # The track, the part of it that has played, and a knob at the end of that part
  rounded_rectangle(ctx, track.left, track.top, track.width, track.height, track.height / 2, background=RGBA(1.0, 1.0, 1.0, 0.35))
  full = track.width * played(v)
  full > 0px && rounded_rectangle(ctx, track.left, track.top, full, track.height, track.height / 2, background=colorant"white")
  knob = 6px * k
  rounded_rectangle(ctx, track.left + full - knob, track.top + track.height / 2 - knob, 2knob, 2knob, knob, background=colorant"white")
  # The times, at the right
  words = strip.children[3]
  f = screen_font(v)
  size = f.size
  said = "$(clock(at(v))) / $(clock(span(m)[2]))"
  ink = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(ink, true)
  Skia.sk_paint_set_color(ink, white)
  blob = Skia.sk_textblob_make_from_string(said, f.raw, Skia.SK_TEXT_ENCODING_UTF8)
  Skia.sk_canvas_draw_text_blob(ctx, blob, flt(words.left + words.width) - flt(text_width(f, said)), flt(words.top + words.height / 2) + size * 0.36f0, ink)
  Skia.sk_textblob_unref(blob)
  Skia.sk_paint_delete(ink)
end

"A line of `words` that's too long for `room` as lines that fit, cut between two words"
caption_lines(f, words, room) = begin
  lines, line = String[], ""
  for word in split(words)
    longer = isempty(line) ? String(word) : line * " " * word
    if flt(text_width(f, longer)) <= room || isempty(line)
      line = longer
    else
      push!(lines, line)
      line = String(word)
    end
  end
  isempty(line) || push!(lines, line)
  lines
end

"""
Draw `words` over the foot of the picture, which is at `left` and `top` and is
`wide` across and `tall` down. Each line is in the middle, in white letters
with a dark edge, so that it reads over a light picture and over a dark one.
The letters are as big as suits the picture.
"""
captions(ctx, words, left, top, wide, tall) = begin
  isempty(strip(words)) && return
  size = Float32(clamp(round(tall * 0.052f0), 11f0, 60f0))
  f = skia_font("Helvetica Neue", size, "Medium")
  lines = reduce(vcat, [caption_lines(f, l, wide * 0.9f0) for l in split(words, '\n') if !isempty(strip(l))], init=String[])
  edge, fill = Skia.sk_paint_new(), Skia.sk_paint_new()
  for paint in (edge, fill)
    Skia.sk_paint_set_antialias(paint, true)
  end
  Skia.sk_paint_set_style(edge, Skia.SK_PAINT_STYLE_STROKE)
  Skia.sk_paint_set_stroke_width(edge, size * 0.16f0)
  Skia.sk_paint_set_stroke_join(edge, Skia.SK_STROKE_JOIN_ROUND)
  Skia.sk_paint_set_color(edge, sk_color(RGBA(0.0, 0.0, 0.0, 0.85)))
  Skia.sk_paint_set_color(fill, sk_color(colorant"white"))
  # The last line sits a little above the foot of the picture, and the lines before it are over it
  step = size * 1.25f0
  y = top + tall - tall * 0.06f0 - step * (length(lines) - 1)
  for line in lines
    x = left + (wide - flt(text_width(f, line))) / 2
    blob = Skia.sk_textblob_make_from_string(line, f.raw, Skia.SK_TEXT_ENCODING_UTF8)
    Skia.sk_canvas_draw_text_blob(ctx, blob, x, y, edge)
    Skia.sk_canvas_draw_text_blob(ctx, blob, x, y, fill)
    Skia.sk_textblob_unref(blob)
    y += step
  end
  Skia.sk_paint_delete(edge)
  Skia.sk_paint_delete(fill)
end

# --- the mouse and the keyboard ----------------------------------------------------

cursor(::Player) = :hand
# A player that fills a screen is under the mouse wherever the mouse is, so it keeps the arrow
cursor(v::VideoPlayer) = v.screen ? :arrow : :hand

within(r, (x, y), slack=0px) = r.left - slack <= x <= r.left + r.width + slack && r.top - slack <= y <= r.top + r.height + slack

"Go to the part of the file that's under `x` on the track"
scrub!(p::Player, x, track) = begin
  from, to = span(media(p))
  goto!(p, from + (to - from) * clamp(Float64((x - track.left) / track.width), 0.0, 1.0))
end

onkey(p::Player, e::KeyPress{Keys.mouse_left}) = begin
  focus(p)
  found = parts(p)
  found === nothing && return handled
  button, track, strip, _, speeds = found
  mouse = e.window.mouse
  if p isa VideoPlayer && p.screen
    # A click while the controls are away brings them back, and plays or stops as a click on the picture does
    hidden = !controls_show(p)
    p.stirred = time()
    hidden && (toggle!(p); return handled)
  end
  if within(button, mouse, 4px)
    toggle!(p)
  elseif speed_shows(p) && within(speeds, mouse, 2px)
    speed!(p, next_speed(speed(p)))
  elseif within(strip, mouse)
    # A click a little past an end of the track goes to that end. A click on the time does nothing.
    if track.left - 6px <= mouse[1] <= track.left + track.width + 6px
      p.drag = true
      scrub!(p, mouse[1], track)
    end
  else
    toggle!(p)   # a click on the picture
  end
  handled
end

# A drag is the player's, so the nodes above don't act on it too
onmouse(p::Player, e::MouseMove) = begin
  # The controls of a player that fills a screen come back when the mouse moves
  p isa VideoPlayer && p.screen && (p.stirred = time(); redraw_in!(p, 0))
  (p.drag && Keys.mouse_left in e.window.keys) || (p.drag = false; return nothing)
  found = parts(p)
  found === nothing || scrub!(p, e.position[1], found[2])
  handled
end

onkey(p::Player, ::KeyPress{Keys.space}) = (toggle!(p); handled)
onkey(p::Player, ::KeyPress{Keys.left}) = (goto!(p, at(p) - 5); handled)
onkey(p::Player, ::KeyPress{Keys.right}) = (goto!(p, at(p) + 5); handled)

# < and > as the keyboard types them, so that they're the keys with < and > on them on any keyboard
ontype(p::Player, e::Typed) = begin
  e.char in ('<', '>') || return nothing
  speed!(p, stepped(speed(p), e.char == '>' ? 1 : -1))
  handled
end

export AudioPlayer, VideoPlayer, toggle!, pause!, speed!, card_bottom, controls_show, has_picture
