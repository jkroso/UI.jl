@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle sk_color
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress MouseMove onkey onmouse flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../Specific"... text_width
@use "../abstract" SemanticUI WrapMode describe focus theme scale handled sized window_of
@use "../draw" draw cursor redraw_in! rect
@use "../media" Playback ready failed duration playing play! pause! seek! picture_size watch! watching picture shown! Levels finished level
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
# Once a click has given a player the keyboard, the space bar plays and stops,
# and ← and → go back and on by 5 seconds.
#
# macOS plays the file, so the players only work on a Mac. One file plays at a
# time: when a player starts, the one that was playing stops. When an app stops
# showing a player, its file stops within a second or two.

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
  # What it remembers between frames
  media::Any = nothing
  aim::Any = nothing
  drag::Bool = false
  still::Still = Still()   # the picture that it shows now
end

"`AudioPlayer(\"song.mp3\")` plays that file. A path that isn't absolute starts from the folder that Julia is in now."
AudioPlayer(path::AbstractString; kwargs...) = AudioPlayer(; path=abspath(path), kwargs...)
"`VideoPlayer(\"holiday.mov\")` plays that file. A path that isn't absolute starts from the folder that Julia is in now."
VideoPlayer(path::AbstractString; kwargs...) = VideoPlayer(; path=abspath(path), kwargs...)

const Player = Union{AudioPlayer,VideoPlayer}

"The file as macOS plays it. It's opened the first time that the player is shown."
media(p::Player) = (p.media === nothing && (p.media = Playback(p.path)); p.media::Playback)

"""
How far through the file it is, in seconds. After a click on the track it's the
time that the click asked for, until the file gets there. The file takes a
moment, and the track would jump back to the old time meanwhile.
"""
at(p::Player) = begin
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

"Go to `s` seconds from the start of the file"
goto!(p::Player, s) = begin
  m = media(p)
  ready(m) || return
  s = clamp(s, 0.0, duration(m))
  seek!(m, s)
  p.aim = (time(), s)
  nothing
end

"""
What a player does each time it's described. It notes that the app still shows
it, which keeps the file playing. It asks for the next frame too, because what
it shows changes with time: within `wait` seconds while the file plays, and
sooner while the file loads or goes to a new time.
"""
tick!(p::Player, wait) = begin
  m = shown!(media(p))
  w = window_of(p)
  # The button can come up while the mouse is somewhere else, and then no move tells the player
  p.drag && w !== nothing && !(Keys.mouse_left in w.keys) && (p.drag = false)
  if !(ready(m) || failed(m)) || p.aim !== nothing
    redraw_in!(p, 1 / 30)
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

"How far through the file it is and how long the file is, like 0:12 / 3:40"
times(p::Player, t) = begin
  long = clock(duration(media(p)))
  text = Text("$(clock(at(p))) / $long", size=sized(12pt, t), color=t.dim, wrap=WrapMode.none, align=TextAlign.Right)
  # Room for its widest time, so that the track keeps its length while the time changes
  Row(width(text_width(text, replace("$long / $long", r"\d" => "0"))), text)
end

"The round button that plays and stops. It's grey until the file can play."
button(p::Player, t, size) = begin
  m = media(p)
  Box(width(size), height(size), radius(size / 2), background(ready(m) ? t.accent : t.track),
    Icon(playing(m) ? "pause-fill" : "play-fill", size=size * 0.56, color=t.on_accent))
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
  Row(card(t)..., height(56px * k), padding(12px * k, 0px), child_gap=12px * k,
    button(a, t, 32px * k),
    Box(width(grow=GrowType.Grow), height(32px * k)),   # the bars are drawn here
    times(a, t))
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
  ready(m) && (w == 0 || h == 0) && return Column(card(t)..., controls)
  # A tall narrow video still has room under it for the controls
  wide = max(240px * k, v.height * (w > 0 && h > 0 ? w / h : 16 / 9))
  Column(width(grow=GrowType.Grow, max=wide), radius(8px), border(1px, :solid, t.line), background(t.surface),
    Image(width(grow=GrowType.Grow), aspect=Float64(wide / v.height)),   # the picture is drawn here
    controls)
end

"""
Where a frame put the parts of a player: its button, its track, the strip that
holds them both and its picture, or nothing for the picture if it has none.
It's nothing when the player shows a sentence in place of its parts.
"""
parts(::AudioPlayer, ui) = length(ui.children) == 3 ? (ui.children[1], ui.children[2], ui, nothing) : nothing
parts(::VideoPlayer, ui) = begin
  strip = isempty(ui.children) ? nothing : ui.children[end]
  (strip isa ConcreteRect && length(strip.children) == 3) || return nothing
  (strip.children[1], strip.children[2], strip, length(ui.children) == 2 ? ui.children[1] : nothing)
end
parts(p::Player) = (r = rect(p); r === nothing ? nothing : parts(p, r))

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

"How much of the file has played: 0 at its start and 1 at its end"
played(p::Player) = (long = duration(media(p)); long > 0 ? clamp(at(p) / long, 0.0, 1.0) : 0.0)

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
  area === nothing || screen(ctx, ui, area, v, m)
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
  edge = Ref(Skia.sk_rect_t(flt(ui.left + 1px), flt(ui.top + 1px), flt(ui.left + ui.width - 1px), flt(ui.top + ui.height - 1px)))
  clip = Skia.sk_path_new()
  Skia.sk_path_add_rounded_rect(clip, edge, flt(7px), flt(7px), Skia.SK_PATH_DIRECTION_CW)
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

# --- the mouse and the keyboard ----------------------------------------------------

cursor(::Player) = :hand

within(r, (x, y), slack=0px) = r.left - slack <= x <= r.left + r.width + slack && r.top - slack <= y <= r.top + r.height + slack

"Go to the part of the file that's under `x` on the track"
scrub!(p::Player, x, track) =
  goto!(p, duration(media(p)) * clamp(Float64((x - track.left) / track.width), 0.0, 1.0))

onkey(p::Player, e::KeyPress{Keys.mouse_left}) = begin
  focus(p)
  found = parts(p)
  found === nothing && return handled
  button, track, strip, _ = found
  mouse = e.window.mouse
  if within(button, mouse, 4px)
    toggle!(p)
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
  (p.drag && Keys.mouse_left in e.window.keys) || (p.drag = false; return nothing)
  found = parts(p)
  found === nothing || scrub!(p, e.position[1], found[2])
  handled
end

onkey(p::Player, ::KeyPress{Keys.space}) = (toggle!(p); handled)
onkey(p::Player, ::KeyPress{Keys.left}) = (goto!(p, at(p) - 5); handled)
onkey(p::Player, ::KeyPress{Keys.right}) = (goto!(p, at(p) + 5); handled)

export AudioPlayer, VideoPlayer, toggle!, pause!
