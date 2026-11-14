@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" sk_color font_metrics
@use "github.com/jkroso/MiniFB.jl" flt
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../../Geometric"...
@use "../../Specific" ConcreteRect
@use "../../abstract" SemanticUI WrapMode describe theme sized Theme inputs
@use "../../draw" draw
@use "./picture"...
@use "./flowchart" flowchart
@use "./sequence" sequence
@use "./state" state
@use "./class" class
@use "./pie" pie
@use Colors: Colorant, RGBA, RGB

# A diagram that's drawn from a few lines of text, in the language of Mermaid
# (mermaid.js.org):
#
#     Mermaid("""
#       flowchart LR
#         A[Write] --> B{Is it clear?}
#         B -- Yes --> C([Send])
#         B -- No --> A
#       """)
#
# The first line of the text says which kind of diagram it is. Five kinds are
# drawn: `flowchart` (or `graph`), `sequenceDiagram`, `stateDiagram-v2`,
# `classDiagram` and `pie`. The file of each kind says what its text can have.
#
# The diagram is drawn in the theme's font and colours, so it suits the page
# that it's on. It's as big as its text needs. In less room than that, the whole
# diagram is drawn smaller. Text that can't be read as a diagram shows a
# sentence that says what's wrong with it, and on which line.

# The kinds of diagram, by the word that the text of one starts with, and what makes the picture of each
const KINDS = Dict{String,Function}("flowchart" => flowchart, "graph" => flowchart, "sequenceDiagram" => sequence,
                                    "stateDiagram" => state, "classDiagram" => class, "pie" => pie)

"The word that says which kind of diagram `code` is: the first word of its first line that isn't a comment"
kind(code::AbstractString) = begin
  lines, _ = statements(code)
  isempty(lines) && return ""
  m = match(r"^[A-Za-z]+", lines[1][2])
  m === nothing ? "" : String(m.match)
end

"""
The picture of the diagram that `code` describes, with its text in the font
`family` and `size` px tall. It's a `Problem` if the code can't be read, or if
it's a kind of diagram that isn't drawn here.
"""
diagram(code::AbstractString; family="Helvetica", size=13.0) = begin
  word = kind(code)
  make = get(KINDS, word, nothing)
  make === nothing && return Problem(0, isempty(word) ? "A diagram starts with its kind, like `flowchart`" : "A `$word` diagram can't be drawn yet")
  try
    make(code, Pen(family, size))::Picture
  catch e
    e isa Problem ? e : Problem(0, "This diagram can't be read")
  end
end

# What `problem` found for each piece of code, so that an app can ask in every frame
const problems = Dict{String,Union{Nothing,String}}()

"What's wrong with the code of a diagram, as a sentence, or nothing if it can be drawn"
problem(code::AbstractString) = begin
  length(problems) > 500 && empty!(problems)
  get!(problems, code) do
    made = diagram(code)
    made isa Problem ? sprint(showerror, made) : nothing
  end
end

@def mutable struct Mermaid <: SemanticUI
  code::String = ""
  # What it remembers between frames: the font that its picture was made for, and the picture
  made::Any = nothing
end

"`Mermaid(code)` draws the diagram that `code` describes"
Mermaid(code::AbstractString; kwargs...) = Mermaid(; code=String(code), kwargs...)

"The picture of the diagram, or the Problem with its code. It's made again when the theme's font changes."
picture!(m::Mermaid, t::Theme) = begin
  key = (m.code, t.family, Float64(convert(px, sized(12pt, t)).value))
  (m.made === nothing || m.made[1] != key) && (m.made = (key, diagram(m.code, family=key[2], size=key[3])))
  m.made[2]
end

# Its picture only changes when its code does, or the theme
inputs(m::Mermaid) = (m.code,)

describe(m::Mermaid) = begin
  t = theme(m)
  made = picture!(m, t)
  made isa Problem && return Row(padding(4px, 8px), Text(sprint(showerror, made), size=sized(12pt, t), color=t.dim))
  (made.w > 0 && made.h > 0) || return Box(height(0px))
  # The diagram is drawn here: as big as it is, or as wide as the room and in proportion
  Column(width(grow=GrowType.Grow, max=px(made.w)), Image(width(grow=GrowType.Grow), aspect=made.w / made.h))
end

# --- colours ----------------------------------------------------------------------

"A colour that's `share` of the way from `a` to `b`"
blend(a, b, share) = begin
  a, b = convert(RGBA{Float64}, a), convert(RGBA{Float64}, b)
  RGBA(a.r + (b.r - a.r) * share, a.g + (b.g - a.g) * share, a.b + (b.b - a.b) * share, 1.0)
end

# The colours of a pie's slices, and of anything else that there's a list of
const TONES = [RGB(0.33, 0.56, 0.86), RGB(0.94, 0.62, 0.27), RGB(0.42, 0.72, 0.47), RGB(0.87, 0.42, 0.42), RGB(0.62, 0.5, 0.82),
               RGB(0.33, 0.72, 0.72), RGB(0.9, 0.76, 0.3), RGB(0.88, 0.54, 0.72), RGB(0.6, 0.62, 0.66), RGB(0.7, 0.54, 0.42)]

"""
The colour that a picture means by `role` in the theme `t`. A role is a name
like :text or :node, or a number, which is a place in a list of colours that
are easy to tell apart. A colour is itself.
"""
colour(t::Theme, role::Colorant) = role
colour(t::Theme, role::Integer) = TONES[mod1(role, length(TONES))]
colour(t::Theme, role::Symbol) =
  role == :text ? t.text :
  role == :dim ? t.dim :
  role == :line ? t.line :
  role == :surface ? t.surface :
  role == :accent ? t.accent :
  role == :on_accent ? t.on_accent :
  role == :on_tone ? RGB(0.1, 0.1, 0.12) :                               # text on one of the colours in TONES
  role == :link ? blend(t.text, t.surface, 0.3) :                        # a line between two boxes
  role == :node ? blend(t.surface, t.accent, 0.1) :                      # a box, and its edge
  role == :edge ? blend(t.surface, t.accent, 0.6) :
  role == :group ? RGBA(convert(RGB{Float64}, t.text), 0.04) :           # a box around boxes
  role == :note ? blend(t.surface, RGB(0.98, 0.8, 0.2), 0.3) :           # a note, and its edge
  role == :note_edge ? blend(t.surface, RGB(0.85, 0.62, 0.1), 0.6) :
  role == :bar ? blend(t.surface, t.text, 0.12) : t.text

# --- drawing ----------------------------------------------------------------------

bounds(x, y, w, h) = Ref(Skia.sk_rect_t(flt(x), flt(y), flt(x + w), flt(y + h)))

"Add a closed shape through `points` to `path`"
polygon!(path, points) = begin
  Skia.sk_path_move_to(path, flt(points[1][1]), flt(points[1][2]))
  foreach(p -> Skia.sk_path_line_to(path, flt(p[1]), flt(p[2])), points[2:end])
  Skia.sk_path_close(path)
end

"""
Add the outline of the shape `s` to `path`. `u` is the size of the diagram's
text, which the corners and the slants are in proportion to.
"""
outline!(path, s::Shape, u) = begin
  x, y, w, h = s.x, s.y, s.w, s.h
  k = s.kind
  cw = Skia.SK_PATH_DIRECTION_CW
  if k == :round
    Skia.sk_path_add_rounded_rect(path, bounds(x, y, w, h), flt(0.5u), flt(0.5u), cw)
  elseif k == :stadium
    Skia.sk_path_add_rounded_rect(path, bounds(x, y, w, h), flt(h / 2), flt(h / 2), cw)
  elseif k == :diamond
    polygon!(path, [(x + w / 2, y), (x + w, y + h / 2), (x + w / 2, y + h), (x, y + h / 2)])
  elseif k in (:circle, :double_circle)
    Skia.sk_path_add_oval(path, bounds(x, y, w, h), cw)
  elseif k == :hexagon
    m = h / 4
    polygon!(path, [(x + m, y), (x + w - m, y), (x + w, y + h / 2), (x + w - m, y + h), (x + m, y + h), (x, y + h / 2)])
  elseif k == :flag
    polygon!(path, [(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x + 0.3h, y + h / 2)])
  elseif k in (:lean_right, :lean_left, :trapezoid, :trapezoid_alt)
    m = 0.35h
    polygon!(path, k == :lean_right ? [(x + m, y), (x + w, y), (x + w - m, y + h), (x, y + h)] :
                   k == :lean_left ? [(x, y), (x + w - m, y), (x + w, y + h), (x + m, y + h)] :
                   k == :trapezoid ? [(x + m, y), (x + w - m, y), (x + w, y + h), (x, y + h)] :
                                     [(x, y), (x + w, y), (x + w - m, y + h), (x + m, y + h)])
  elseif k == :cylinder
    # A drum: a lid that's an oval, straight sides, and a round bottom
    r = 0.5u
    bulge = 4r / 3   # a curve that's pulled this far is as tall as half an oval of the height `r`
    Skia.sk_path_move_to(path, flt(x), flt(y + r))
    Skia.sk_path_cubic_to(path, flt(x), flt(y + r - bulge), flt(x + w), flt(y + r - bulge), flt(x + w), flt(y + r))
    Skia.sk_path_line_to(path, flt(x + w), flt(y + h - r))
    Skia.sk_path_cubic_to(path, flt(x + w), flt(y + h - r + bulge), flt(x), flt(y + h - r + bulge), flt(x), flt(y + h - r))
    Skia.sk_path_close(path)
  elseif k == :plain
    Skia.sk_path_add_rect(path, bounds(x, y, w, h), cw)
  else
    Skia.sk_path_add_rounded_rect(path, bounds(x, y, w, h), flt(0.18u), flt(0.18u), cw)
  end
end

"Add the lines that a shape has inside its outline to `path`: the bars of a subroutine, the lid of a drum, the ring of a double circle"
details!(path, s::Shape, u) = begin
  x, y, w, h = s.x, s.y, s.w, s.h
  if s.kind == :subroutine
    for bar in (x + 0.55u, x + w - 0.55u)
      Skia.sk_path_move_to(path, flt(bar), flt(y))
      Skia.sk_path_line_to(path, flt(bar), flt(y + h))
    end
  elseif s.kind == :cylinder
    r = 0.5u
    Skia.sk_path_move_to(path, flt(x), flt(y + r))
    Skia.sk_path_cubic_to(path, flt(x), flt(y + r + 4r / 3), flt(x + w), flt(y + r + 4r / 3), flt(x + w), flt(y + r))
  elseif s.kind == :double_circle
    Skia.sk_path_add_oval(path, bounds(x + 0.3u, y + 0.3u, w - 0.6u, h - 0.6u), Skia.SK_PATH_DIRECTION_CW)
  end
end

"Make `paint` draw lines that are `thick` wide in `colour`, with the dashes that `dash` names"
pen!(paint, colour, thick, dash) = begin
  Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1))
  Skia.sk_paint_set_color(paint, sk_color(colour))
  Skia.sk_paint_set_stroke_width(paint, flt(thick))
  Skia.sk_paint_set_stroke_join(paint, Skia.SK_STROKE_JOIN_ROUND)
  Skia.sk_paint_set_stroke_cap(paint, dash == :solid ? Skia.SK_STROKE_CAP_ROUND : Skia.SK_STROKE_CAP_BUTT)
  if dash == :solid
    Skia.sk_paint_set_path_effect(paint, C_NULL)
  else
    on, off = dash == :dotted ? (2.2thick, 2.8thick) : (5thick, 3.5thick)
    lengths = Float32[max(on, 2.0), max(off, 2.5)]
    effect = Skia.sk_path_effect_create_dash(lengths, Int32(2), 0f0)
    Skia.sk_paint_set_path_effect(paint, effect)
    Skia.sk_path_effect_unref(effect)
  end
end

"Make `paint` fill shapes with `colour`"
fill!(paint, colour) = begin
  Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0))
  Skia.sk_paint_set_color(paint, sk_color(colour))
  Skia.sk_paint_set_path_effect(paint, C_NULL)
end

show!(ctx, paint, t::Theme, u, s::Shape) = begin
  path = Skia.sk_path_new()
  outline!(path, s, u)
  if s.fill !== nothing
    fill!(paint, colour(t, s.fill))
    Skia.sk_canvas_draw_path(ctx, path, paint)
  end
  if s.line !== nothing && s.thick > 0
    details!(path, s, u)
    pen!(paint, colour(t, s.line), s.thick, s.dash)
    Skia.sk_canvas_draw_path(ctx, path, paint)
  end
  Skia.sk_path_delete(path)
end

# How much of an arrow's length the line under it stops short by, so that the line doesn't show past its point
const SHORT = Dict(:arrow => 0.7, :circle => 0.7, :cross => 0.0, :triangle => 1.0, :diamond => 1.4, :hollow => 1.4, :open => 0.0, :none => 0.0)

"""
Draw what the end of a line has, with its point at `at`. The line comes to the
point along (`dx`, `dy`), which is one long.
"""
tip!(ctx, paint, kind::Symbol, at, dx, dy, long, ink, thick, surface) = begin
  kind == :none && return
  x, y = at
  # A point that's `along` back from the tip and `side` to the left of the line
  spot(along, side) = (x - dx * along - dy * side, y - dy * along + dx * side)
  path = Skia.sk_path_new()
  if kind == :arrow
    polygon!(path, [at, spot(long, 0.36long), spot(0.8long, 0.0), spot(long, -0.36long)])
    fill!(paint, ink)
  elseif kind == :circle
    Skia.sk_path_add_circle(path, flt(x - dx * 0.35long), flt(y - dy * 0.35long), flt(0.35long), Skia.SK_PATH_DIRECTION_CW)
    fill!(paint, ink)
  elseif kind in (:diamond, :hollow)
    polygon!(path, [at, spot(0.7long, 0.34long), spot(1.4long, 0.0), spot(0.7long, -0.34long)])
    if kind == :hollow
      # An empty diamond is filled with the colour behind it, so that the line doesn't show in it
      fill!(paint, surface)
      Skia.sk_canvas_draw_path(ctx, path, paint)
      pen!(paint, ink, thick, :solid)
    else
      fill!(paint, ink)
    end
  elseif kind == :triangle
    polygon!(path, [at, spot(long, 0.5long), spot(long, -0.5long)])
    fill!(paint, surface)
    Skia.sk_canvas_draw_path(ctx, path, paint)
    pen!(paint, ink, thick, :solid)
  elseif kind == :open
    for side in (0.4long, -0.4long)
      Skia.sk_path_move_to(path, flt.(spot(long, side))...)
      Skia.sk_path_line_to(path, flt(x), flt(y))
    end
    pen!(paint, ink, thick, :solid)
  elseif kind == :cross
    for (a, b) in ((spot(0.75long, 0.35long), spot(0.05long, -0.35long)), (spot(0.75long, -0.35long), spot(0.05long, 0.35long)))
      Skia.sk_path_move_to(path, flt.(a)...)
      Skia.sk_path_line_to(path, flt.(b)...)
    end
    pen!(paint, ink, 1.3thick, :solid)
  end
  Skia.sk_canvas_draw_path(ctx, path, paint)
  Skia.sk_path_delete(path)
end

"The way that a line goes from `a` to `b`, one long, or nothing if they're the same point"
towards(a, b) = begin
  dx, dy = b[1] - a[1], b[2] - a[2]
  d = hypot(dx, dy)
  d < 1e-6 ? nothing : (dx / d, dy / d)
end

show!(ctx, paint, t::Theme, u, s::Stroke) = begin
  points = copy(s.points)
  length(points) < 2 && return
  ink = colour(t, s.colour)
  # The way that the line goes at each end: from the nearest point that isn't the end itself
  last_way = something((towards(p, points[end]) for p in reverse(points[1:end-1]))..., (1.0, 0.0))
  first_way = something((towards(p, points[1]) for p in points[2:end])..., (1.0, 0.0))
  ends = (points[1], points[end])
  # The line stops short of the point of an arrow. The points that pull a curve to its end move back with the end.
  back(p, way, by) = (p[1] - way[1] * by, p[2] - way[2] * by)
  by = SHORT[s.to] * s.tip
  if by > 0
    points[end] = back(points[end], last_way, by)
    s.curved && (points[end-1] = back(points[end-1], last_way, by))
  end
  by = SHORT[s.from] * s.tip
  if by > 0
    points[1] = back(points[1], first_way, by)
    s.curved && (points[2] = back(points[2], first_way, by))
  end
  path = Skia.sk_path_new()
  Skia.sk_path_move_to(path, flt(points[1][1]), flt(points[1][2]))
  if s.curved
    for i in 2:3:length(points)-2
      a, b, c = points[i], points[i+1], points[i+2]
      Skia.sk_path_cubic_to(path, flt(a[1]), flt(a[2]), flt(b[1]), flt(b[2]), flt(c[1]), flt(c[2]))
    end
  else
    foreach(p -> Skia.sk_path_line_to(path, flt(p[1]), flt(p[2])), points[2:end])
  end
  Skia.sk_canvas_save(ctx)
  # The line isn't drawn where its label is
  for (x, y, w, h) in s.around
    Skia.sk_canvas_clip_rect_with_operation(ctx, bounds(x, y, w, h), Skia.SK_CLIP_OP_DIFFERENCE, true)
  end
  pen!(paint, ink, s.thick, s.dash)
  Skia.sk_canvas_draw_path(ctx, path, paint)
  Skia.sk_canvas_restore(ctx)
  Skia.sk_path_delete(path)
  tip!(ctx, paint, s.to, ends[2], last_way..., s.tip, ink, s.thick, t.surface)
  tip!(ctx, paint, s.from, ends[1], first_way..., s.tip, ink, s.thick, t.surface)
end

show!(ctx, paint, t::Theme, u, w::Words) = begin
  f = font(Pen(t.family, u); size=w.size, bold=w.bold, italic=w.italic)
  x = w.align == :left ? w.x : w.x - wide(Pen(t.family, u), w.text; size=w.size, bold=w.bold, italic=w.italic) / (w.align == :right ? 1 : 2)
  fill!(paint, colour(t, w.colour))
  blob = Skia.sk_textblob_make_from_string(w.text, f.raw, Skia.SK_TEXT_ENCODING_UTF8)
  # The middle of a line of text is the middle of its capital letters
  Skia.sk_canvas_draw_text_blob(ctx, blob, flt(x), flt(w.y + font_metrics(f).capHeight / 2), paint)
  Skia.sk_textblob_unref(blob)
end

show!(ctx, paint, t::Theme, u, s::Slice) = begin
  path = Skia.sk_path_new()
  if s.to - s.from >= 2pi - 1e-6
    Skia.sk_path_add_circle(path, flt(s.x), flt(s.y), flt(s.r), Skia.SK_PATH_DIRECTION_CW)
  else
    Skia.sk_path_move_to(path, flt(s.x), flt(s.y))
    # Skia measures an angle in degrees from 3 o'clock, and a slice is measured from 12 o'clock
    Skia.sk_path_arc_to_with_oval(path, bounds(s.x - s.r, s.y - s.r, 2s.r, 2s.r), flt(rad2deg(s.from) - 90), flt(rad2deg(s.to - s.from)), false)
    Skia.sk_path_close(path)
  end
  fill!(paint, colour(t, s.fill))
  Skia.sk_canvas_draw_path(ctx, path, paint)
  # A thin line in the colour behind the pie parts each slice from the next
  pen!(paint, t.surface, 0.08u, :solid)
  Skia.sk_canvas_draw_path(ctx, path, paint)
  Skia.sk_path_delete(path)
end

draw(ctx, size, ui::ConcreteRect, m::Mermaid) = begin
  m.made === nothing && return
  made = m.made[2]
  (made isa Picture && made.w > 0) || return
  t, u = theme(m), m.made[1][3]
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_canvas_save(ctx)
  Skia.sk_canvas_translate(ctx, flt(ui.left), flt(ui.top))
  # In less room than the picture needs, all of it is drawn smaller
  k = flt(ui.width) / flt(made.w)
  Skia.sk_canvas_scale(ctx, k, k)
  foreach(item -> show!(ctx, paint, t, u, item), made.items)
  Skia.sk_canvas_restore(ctx)
  Skia.sk_paint_delete(paint)
end

export Mermaid, diagram, problem, kind
