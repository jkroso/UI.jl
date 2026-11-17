@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" sk_color font_metrics
@use "github.com/jkroso/MiniFB.jl" flt Keys KeyPress KeyRelease MouseMove onkey onmouse
@use Skia
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../../Geometric"...
@use "../../Specific" ConcreteRect
@use "../../abstract" SemanticUI WrapMode describe theme sized scale Theme inputs handled focus window_of kept!
@use "../../draw" draw redraw_in! ishovered cursor show_menu! show_tooltip! hide_tooltip!
@use "../TextInput" TextInput
@use "../Icon" Icon
@use "./picture"...
@use "./flowchart" flowchart flowchart_edits
@use "./sequence" sequence sequence_edits
@use "./state" state state_edits
@use "./class" class class_edits
@use "./pie" pie pie_edits
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
#
# With `editing=true` the diagram can be changed where it's drawn:
#
#     Mermaid(code, editing=true, onchange=m -> save(m.code))
#
#   - A click selects a box, a line or another part. It glows.
#   - Two clicks on a part, or Return, let you type its words where they are.
#     Return takes them and Esc leaves the old ones.
#   - The buttons over the diagram are the tools for the part that's selected,
#     or for the whole diagram while nothing is: add a box, draw a line from
#     this box to the one that's clicked next, change its shape, take it away.
#   - ⌫ takes the selected part away.
#   - A box that a line can be drawn from shows a point on its edge while the
#     mouse is over it. Drag the point onto another box to draw a line to it.
#
# Each change writes the code again, in `code`, and only the lines that the
# change is about. A box has no place of its own in the code, so the diagram
# is laid out again after each change and nothing is dragged.

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

# How each kind of diagram is changed, by the word that its text starts with. Each has four functions:
# `said(code, kind, key)` is the words of a part as you type them, or nothing for a part that has none.
# `reword(code, kind, key, text)` is the code with other words for the part.
# `tools(code, kind, key)` lists the tools for the part that's selected, or for the diagram with the kind :none.
# `use(code, tool, kind, key, arg)` uses a tool, and returns the new code, the part that's selected after it,
# and whether its words are typed next.
const EDITORS = Dict{String,Any}("flowchart" => flowchart_edits, "graph" => flowchart_edits, "sequenceDiagram" => sequence_edits,
                                "stateDiagram" => state_edits, "classDiagram" => class_edits, "pie" => pie_edits)

@def mutable struct Mermaid <: SemanticUI
  code::String = ""
  # What it remembers between frames: the font that its picture was made for, and the picture
  made::Any = nothing
  editing::Bool = false      # its parts can be selected and changed
  bar::Bool = true           # while it can be changed, its tools show as buttons over it. An app with buttons of its own turns this off.
  onchange::Any = nothing    # `onchange(mermaid)` runs after a change to its code
  keys::Any = nothing        # the node that takes the keyboard when words have been typed. Nothing means the diagram itself.
  picked::Any = nothing      # the part that's selected: its kind and its key
  typing::Any = nothing      # the part whose words are being typed: its kind and its key
  waiting::Any = nothing     # the name of the tool that waits for a click on another part
  field::Any = nothing       # the text field that holds the words that are typed. It isn't shown: the picture shows its words.
  clicked::NTuple{3,Float64} = (0.0, 0.0, 0.0)             # when and where the last click was, to tell two clicks from one
  place::NTuple{3,Float64} = (0.0, 0.0, 1.0)               # where its picture was last drawn: its left, its top, and how many px of the window a px of it is
  typed_in::NTuple{4,Float64} = (0.0, 0.0, 0.0, 0.0)       # where a click puts the caret in the words that are typed, as last drawn, in the picture
  hovered::Any = nothing     # the Part under the mouse that a line can be drawn from, which shows its point
  on_point::Bool = false     # the mouse is on the point of the part that's hovered
  joining::Any = nothing     # while a line is dragged from a part's point: the part's kind and key, the tool that draws it, and where the mouse is in the picture
end

"`Mermaid(code)` draws the diagram that `code` describes"
Mermaid(code::AbstractString; kwargs...) = Mermaid(; code=String(code), kwargs...)

"The picture of the diagram, or the Problem with its code. It's made again when the theme's font changes."
picture!(m::Mermaid, t::Theme) = begin
  key = (m.code, t.family, Float64(convert(px, sized(12pt, t)).value))
  (m.made === nothing || m.made[1] != key) && (m.made = (key, diagram(m.code, family=key[2], size=key[3])))
  m.made[2]
end

# Its picture only changes when its code does, or the theme. Its buttons change with what's selected.
inputs(m::Mermaid) = (m.code, m.editing, m.bar, m.picked, m.typing, m.waiting)

describe(m::Mermaid) = begin
  t = theme(m)
  made = picture!(m, t)
  made isa Problem && return Row(padding(4px, 8px), Text(sprint(showerror, made), size=sized(12pt, t), color=t.dim))
  (made.w > 0 && made.h > 0) || return Box(height(0px))
  # The caret in the words that are typed blinks
  m.typing === nothing || redraw_in!(m, 0.5)
  # The diagram is drawn here: as big as it is, or as wide as the room and in proportion
  image = Image(width(grow=GrowType.Grow), aspect=made.w / made.h)
  buttons = m.bar ? tool_buttons(m) : ()
  isempty(buttons) && return Column(width(grow=GrowType.Grow, max=px(made.w)), image)
  k = scale(t)
  Column(width(grow=GrowType.Grow), Alignment.Start, child_gap=6px * k,
    Row(child_gap=2px * k, padding(2px * k), radius(8px * k), background(t.surface), border(1px, :solid, t.line), buttons...),
    Column(width(grow=GrowType.Grow, max=px(made.w)), image))
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

"""
Draw nothing in the boxes `around` from now on, each a left, a top, a width and
a height. The clip is one shape, the room to draw in with holes where the boxes
are, so that a canvas that writes SVG can keep it too. An SVG can't keep a clip
that leaves a box out.
"""
clip_out!(ctx, around) = begin
  room = Ref(Skia.sk_rect_t(0f0, 0f0, 0f0, 0f0))
  Skia.sk_canvas_get_local_clip_bounds(ctx, room)
  whole, boxes, kept = Skia.sk_path_new(), Skia.sk_path_new(), Skia.sk_path_new()
  Skia.sk_path_add_rect(whole, room, Skia.SK_PATH_DIRECTION_CW)
  foreach(((x, y, w, h),) -> Skia.sk_path_add_rect(boxes, bounds(x, y, w, h), Skia.SK_PATH_DIRECTION_CW), around)
  Skia.sk_path_op(whole, boxes, Skia.SK_PATH_OP_DIFFERENCE, kept)
  Skia.sk_canvas_clip_path_with_operation(ctx, kept, Skia.SK_CLIP_OP_INTERSECT, true)
  foreach(Skia.sk_path_delete, (whole, boxes, kept))
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
  isempty(s.around) || clip_out!(ctx, s.around)
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
  # The picture is the last thing in it, under its buttons when it has them
  ui = isempty(ui.children) ? ui : ui.children[end]
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_canvas_save(ctx)
  Skia.sk_canvas_translate(ctx, flt(ui.left), flt(ui.top))
  # In less room than the picture needs, all of it is drawn smaller
  k = flt(ui.width) / flt(made.w)
  m.place = (Float64(ui.left.value), Float64(ui.top.value), Float64(k))
  Skia.sk_canvas_scale(ctx, k, k)
  # The words of the part that are being typed are drawn as they're typed, in their place.
  # A box that's too small for them is drawn bigger, in its own place among the rest.
  typing = m.editing && m.typing !== nothing ? part(m, m.typing) : nothing
  typed = typing === nothing ? Int[] : own_words(m, typing)
  big = typing === nothing ? nothing : grown(m, typing)
  for (i, item) in enumerate(made.items)
    i in typed && continue
    show!(ctx, paint, t, u, big !== nothing && first(big) == i ? last(big) : item)
  end
  if m.editing
    chosen = part(m, m.picked)
    if chosen !== nothing && big !== nothing && m.picked == m.typing
      s = last(big)
      chosen = Part(chosen.kind, chosen.key, (s.x, s.y, s.w, s.h), chosen.path, chosen.shape, chosen.words, chosen.room)
    end
    chosen === nothing || glow!(ctx, paint, t, u, chosen)
    m.typing === nothing || draw_typing(ctx, paint, t, u, m)
    draw_point(ctx, paint, t, u, m)
  end
  Skia.sk_canvas_restore(ctx)
  Skia.sk_paint_delete(paint)
end

# --- changing it ------------------------------------------------------------------

"The picture of the diagram as its code is now, or the Problem with the code, or nothing before it has been shown"
pictured(m::Mermaid) = begin
  m.made === nothing && return nothing
  (code, family, size), made = m.made
  code == m.code || (m.made = ((m.code, family, size), diagram(m.code; family, size)))
  m.made[2]
end

"How the kind of diagram that `m` shows is changed, or nothing for a kind that isn't"
editor(m::Mermaid) = get(EDITORS, kind(m.code), nothing)

"True while the parts of `m` can be selected and changed"
changes(m::Mermaid) = m.editing && editor(m) !== nothing && pictured(m) isa Picture

"The part of the picture that `which` names, a kind and a key, or nothing when the picture has none like it"
part(m::Mermaid, which) = begin
  which === nothing && return nothing
  made = pictured(m)
  made isa Picture || return nothing
  i = findfirst(p -> (p.kind, p.key) == which, made.parts)
  i === nothing ? nothing : made.parts[i]
end

"How far the place (x, y) is from the line through `path`"
far(path::Vector{Point}, x, y) = begin
  least = Inf
  for i in 1:length(path)-1
    (ax, ay), (bx, by) = path[i], path[i+1]
    dx, dy = bx - ax, by - ay
    t = dx == 0 && dy == 0 ? 0.0 : clamp(((x - ax) * dx + (y - ay) * dy) / (dx^2 + dy^2), 0.0, 1.0)
    least = min(least, hypot(x - ax - t * dx, y - ay - t * dy))
  end
  least
end

"True when the place (x, y) is in the shape that has its corners at `points`"
within(points::Vector{Point}, x, y) = begin
  inside = false
  for i in eachindex(points)
    (ax, ay), (bx, by) = points[i], points[mod1(i + 1, length(points))]
    (ay > y) != (by > y) && x < ax + (y - ay) * (bx - ax) / (by - ay) && (inside = !inside)
  end
  inside
end

"""
The part of the picture at the place (x, y) of it, or nothing. A line is at
the place when it's no more than `near` px from it. The parts are asked in
the order that the picture lists them, so a box is found before a line that
goes under it. With `kind`, only parts of that kind are asked.
"""
part_at(m::Mermaid, x, y; near=nothing, kind=nothing) = begin
  made = pictured(m)
  made isa Picture || return nothing
  near = something(near, 0.5 * m.made[1][3])
  for p in made.parts
    kind === nothing || p.kind == kind || continue
    bx, by, bw, bh = p.box
    over = bx <= x <= bx + bw && by <= y <= by + bh
    hit = p.shape == :area ? within(p.path, x, y) : isempty(p.path) ? over : (bw > 0 && over) || far(p.path, x, y) <= near
    hit && return p
  end
  nothing
end

"The text field that holds the words that are typed into the picture"
field!(m::Mermaid) = begin
  if m.field === nothing
    m.field = TextInput(placeholder="")
    setfield!(m.field, :parent, m)
  end
  m.field
end

"Give the keyboard to the diagram, or to the node that an app gave it for that"
keyboard!(m::Mermaid) = focus(something(m.keys, m))

"""
Give the diagram the code `code`, with the part `picked` selected, if it's
code that can be drawn. Returns true when the code changed.
"""
change!(m::Mermaid, code::AbstractString, picked=m.picked) = begin
  if code != m.code
    family, size = m.made === nothing ? ("Helvetica", 13.0) : m.made[1][2:3]
    made = diagram(code; family, size)
    made isa Problem && return false
    m.code = String(code)
    m.made === nothing || (m.made = ((m.code, family, size), made))
    m.picked = picked
    m.onchange === nothing || m.onchange(m)
    return true
  end
  m.picked = picked
  false
end

"""
The tools for the part that's selected, or for the whole diagram while nothing
is. A diagram that can't be changed has none.
"""
tools(m::Mermaid) = begin
  changes(m) || return Tool[]
  part(m, m.picked) === nothing && (m.picked = nothing)
  kind, key = something(m.picked, (:none, nothing))
  editor(m).tools(m.code, kind, key)::Vector{Tool}
end

"""
Use the tool called `name`. `arg` is one of its choices, or the part to use it
with, a kind and a key, for a tool that needs one. Without `arg`, a tool that
needs a part waits for the next click on one. Returns true when it did something.
"""
use!(m::Mermaid, name::Symbol, arg=nothing) = begin
  changes(m) || return false
  m.typing === nothing || settle!(m)
  i = findfirst(t -> t.name == name, tools(m))
  i === nothing && return false
  tool = tools(m)[i]
  if arg === nothing
    isempty(tool.choices) || return false
    if tool.target
      # A second click on the tool stops it waiting
      m.waiting = m.waiting == name ? nothing : name
      return true
    end
  end
  m.waiting = nothing
  kind, key = something(m.picked, (:none, nothing))
  code, picked, typing = editor(m).use(m.code, name, kind, key, arg)
  changed = change!(m, code, picked)
  changed && typing && retype!(m, all=true)
  changed
end

"""
Start typing the words of the part that's selected, where they are in the
picture. With `all` they're selected, so what's typed takes their place.
Returns true when the part has words.
"""
retype!(m::Mermaid; all=false) = begin
  (changes(m) && part(m, m.picked) !== nothing) || return false
  text = editor(m).said(m.code, m.picked...)
  text === nothing && return false
  f = field!(m)
  f.text = text
  f.cursor = length(text)
  f.anchor = all ? 0 : f.cursor
  f.last_action = time()
  m.typing = m.picked
  focus(f)
  true
end

"Take the words that were typed as the words of the part. Returns true when words were being typed."
settle!(m::Mermaid) = begin
  m.typing === nothing && return false
  which, m.typing = m.typing, nothing
  text = m.field.text
  if text != editor(m).said(m.code, which...)
    # A part that's named by its words has another key after this
    new = editor(m).reword(m.code, which..., text)
    new isa Tuple ? change!(m, new[1], new[2]) : change!(m, new, which)
  end
  keyboard!(m)
  true
end

"Stop typing, and leave the words of the part as they were. Returns true when words were being typed."
cancel!(m::Mermaid) = begin
  m.typing === nothing && return false
  m.typing = nothing
  keyboard!(m)
  true
end

"""
The places in the list of what the picture of `m` draws of the words that the
part `p` shows: the lines of text in the room that its words have.
"""
own_words(m::Mermaid, p::Part) = begin
  (cx, cy), (rw, rh) = p.words, p.room
  slack = 0.3m.made[1][3]
  findall(m.made[2].items) do item
    item isa Words && abs(item.y - cy) <= rh / 2 + slack && abs(item.x - cx) <= rw / 2 + slack
  end
end

"""
The words that are being typed into the part `p`, as they're drawn: with the
look of the part's own words, and with their left where the first character
goes. They start where the part's words start. Words that are in the middle of
their room stay in the middle of it as they get longer.
"""
typed_words(m::Mermaid, p::Part) = begin
  own = [m.made[2].items[i] for i in own_words(m, p)]
  u = m.made[1][3]
  look = isempty(own) ? Words("", p.words..., :middle, u, false, false, :text) : own[1]
  text = m.field.text
  long = wide(Pen(m.made[1][2], u), text; size=look.size, bold=look.bold, italic=look.italic)
  left = look.align == :left ? look.x : look.align == :right ? look.x - long : p.words[1] - long / 2
  Words(text, left, p.words[2], :left, look.size, look.bold, look.italic, look.colour)
end

"How wide the first `n` characters of the words `w` are"
wide_to(m::Mermaid, w::Words, n) = wide(Pen(m.made[1][2], m.made[1][3]), first(w.text, n); size=w.size, bold=w.bold, italic=w.italic)

"How much wider the words that are typed into the part `p` are than its own words"
too_wide(m::Mermaid, p::Part) = (w = typed_words(m, p); wide_to(m, w, length(w.text)) - p.room[1])

"""
The shape that the part `p` is drawn with, made big enough for the words that
are typed in it, after its place in the list of what the picture draws. It's
nothing when the words fit, or when the part isn't drawn with a shape of its own.
"""
grown(m::Mermaid, p::Part) = begin
  items = m.made[2].items
  i = findfirst(s -> s isa Shape && all(isapprox.((s.x, s.y, s.w, s.h), p.box; atol=0.01)), items)
  i === nothing && return nothing
  more = too_wide(m, p)
  more > 0 || return nothing
  s = items[i]
  # A diamond is narrower above and below its middle, so it grows more than the words do
  s.kind == :diamond && (more *= s.h / max(s.h - p.room[2], 1.0))
  # A circle stays round
  tall = s.kind in (:circle, :double_circle) ? more : 0.0
  i => Shape(s.kind, s.x - more / 2, s.y - tall / 2, s.w + more, s.h + tall, s.fill, s.line, s.thick, s.dash)
end

"The colour of the picture behind the place (x, y): the theme's surface, with the shapes that fill that place over it"
behind(m::Mermaid, t::Theme, x, y) = begin
  c = convert(RGBA{Float64}, t.surface)
  for s in m.made[2].items
    (s isa Shape && s.fill !== nothing && s.x <= x <= s.x + s.w && s.y <= y <= s.y + s.h) || continue
    f = convert(RGBA{Float64}, colour(t, s.fill))
    c = RGBA(c.r + (f.r - c.r) * f.alpha, c.g + (f.g - c.g) * f.alpha, c.b + (f.b - c.b) * f.alpha, 1.0)
  end
  c
end

"The place among the characters that are being typed that's nearest to `x` in the picture"
typed_index(m::Mermaid, x) = begin
  w = typed_words(m, part(m, m.typing))
  argmin(n -> abs(w.x + wide_to(m, w, n) - x), 0:length(w.text))
end

"""
A click at the place (x, y) of the picture. It selects the part there, or
nothing. The second of two clicks on a part starts typing its words. While a
tool waits for a part, the click gives it one. Returns true when the click
was on a part, or changed what's selected.
"""
pick_at!(m::Mermaid, x, y; near=nothing) = begin
  changes(m) || return false
  at, cx, cy = m.clicked
  twice = time() - at < 0.4 && hypot(x - cx, y - cy) < 4
  m.clicked = (time(), Float64(x), Float64(y))
  if m.typing !== nothing
    # A click in the words that are typed puts the caret there
    bx, by, bw, bh = m.typed_in
    if bx <= x <= bx + bw && by <= y <= by + bh
      f = m.field
      f.cursor = f.anchor = typed_index(m, x)
      f.last_action = time()
      focus(f)   # an app may have given the keyboard to the node that took the click
      return true
    end
    settle!(m)
  end
  hit = part_at(m, x, y; near)
  if m.waiting !== nothing
    hit === nothing ? (m.waiting = nothing) : use!(m, m.waiting, (hit.kind, hit.key))
    return true
  end
  hit === nothing && return (had = m.picked !== nothing; m.picked = nothing; had)
  which = (hit.kind, hit.key)
  again = twice && m.picked == which
  m.picked = which
  again && retype!(m)
  true
end

"""
What the key `K` does to a diagram that can be changed. Return types the words
of the part that's selected, and takes the words that are typed. ⌫ takes the
part away. Esc stops typing, or stops a tool waiting, or selects nothing.
Returns true when the key did something.
"""
key!(m::Mermaid, K) = begin
  changes(m) || return false
  if m.typing !== nothing
    return K == Keys.enter ? settle!(m) : K == Keys.escape ? cancel!(m) : false
  end
  if K == Keys.escape
    m.waiting !== nothing && return (m.waiting = nothing; true)
    return (had = m.picked !== nothing; m.picked = nothing; had)
  end
  part(m, m.picked) === nothing && return false
  K == Keys.enter && return retype!(m)
  K in (Keys.backspace, Keys.delete) && return use!(m, :delete)
  false
end

# --- drawing a line by dragging -----------------------------------------------------

"The name of the tool that draws a line from the part `which` to another part, or nothing when it has none"
joiner(m::Mermaid, which) = begin
  (changes(m) && which !== nothing) || return nothing
  tools = editor(m).tools(m.code, which...)::Vector{Tool}
  i = findfirst(t -> t.target, tools)
  i === nothing ? nothing : tools[i].name
end

"The way that the lines of a diagram go, as its code says: :right, :left, :down or :up"
flow(code::AbstractString) = begin
  lines, _ = statements(code)
  isempty(lines) && return :down
  said = match(r"^(?:flowchart|graph)\s+(LR|RL|TB|TD|BT)\b", lines[1][2])
  if said === nothing
    i = findfirst(l -> occursin(r"^direction\s+(LR|RL|TB|TD|BT)\b", l[2]), lines)
    said = i === nothing ? nothing : match(r"^direction\s+(LR|RL|TB|TD|BT)\b", lines[i][2])
  end
  # The people of a sequence diagram are in a row, and their messages go across
  way = said === nothing ? (kind(code) == "sequenceDiagram" ? "LR" : "TB") : said[1]
  way == "LR" ? :right : way == "RL" ? :left : way == "BT" ? :up : :down
end

"Where the point that a line is dragged from is on the part `p`: the middle of the side that the diagram's lines go out of"
point_of(m::Mermaid, p::Part) = begin
  x, y, w, h = p.box
  way = flow(m.code)
  way == :right ? (x + w, y + h / 2) : way == :left ? (x, y + h / 2) : way == :up ? (x + w / 2, y) : (x + w / 2, y + h)
end

"How near the point of a part the mouse has to be to be on it, in px of the picture. An app gives `near` for a diagram that's drawn small."
reach(m::Mermaid, near) = max(0.7m.made[1][3], something(near, 0.0))

"""
The mouse is at the place (x, y) of the picture. The part under it shows its
point, if a line can be drawn from it. The point stays while the mouse is on
it, though half of it is outside the part. Returns true when what shows changed.
"""
hover_at!(m::Mermaid, x, y; near=nothing) = begin
  was, on = m.hovered, m.on_point
  if changes(m)
    over = was !== nothing && hypot(x - point_of(m, was)[1], y - point_of(m, was)[2]) <= reach(m, near)
    p = over ? was : part_at(m, x, y; near)
    p === was || (m.hovered = p !== nothing && joiner(m, (p.kind, p.key)) !== nothing ? p : nothing)
    m.on_point = m.hovered !== nothing && hypot(x - point_of(m, m.hovered)[1], y - point_of(m, m.hovered)[2]) <= reach(m, near)
  else
    m.hovered, m.on_point = nothing, false
  end
  m.hovered !== was || m.on_point != on
end

"Show no part's point, as when the mouse has left the diagram. Returns true when one showed."
unhover!(m::Mermaid) = begin
  had = m.hovered !== nothing
  m.hovered, m.on_point = nothing, false
  had
end

"""
The mouse button went down at the place (x, y) of the picture. On the point of
a part, it starts a line from the part, which follows the mouse until the
button comes up. Returns true when it did.
"""
press_at!(m::Mermaid, x, y; near=nothing) = begin
  hover_at!(m, x, y; near)
  m.on_point || return false
  p = m.hovered
  m.typing === nothing || settle!(m)
  m.waiting = nothing
  m.joining = ((p.kind, p.key), joiner(m, (p.kind, p.key)), Float64(x), Float64(y))
  true
end

"The mouse moved to the place (x, y) of the picture with its button down. A line that's dragged follows it. Returns true when one is."
drag_to!(m::Mermaid, x, y) = begin
  j = m.joining
  j === nothing && return false
  m.joining = (j[1], j[2], Float64(x), Float64(y))
  true
end

"The part that the line that's dragged would go to: a part of the same kind as the one it's from, under the mouse"
landing(m::Mermaid) = begin
  j = m.joining
  j === nothing && return nothing
  p = part_at(m, j[3], j[4]; kind=j[1][1])
  p === nothing || (p.kind, p.key) == j[1] ? nothing : p
end

"""
The mouse button came up at the place (x, y) of the picture. A line that was
dragged from a part onto another one is drawn, and then it's selected. Let go
of it anywhere else, and the part it's from is selected. Returns true when a
line was dragged.
"""
let_go_at!(m::Mermaid, x, y) = begin
  drag_to!(m, x, y) || return false
  to, (from, tool) = landing(m), m.joining
  m.joining = nothing
  m.picked = from
  to === nothing || use!(m, tool, (to.kind, to.key))
  true
end

"""
Draw the point of the part that's hovered, on its edge. While a line is dragged
from it, draw the line from the point to the mouse, and make the part that it
would go to glow.
"""
draw_point(ctx, paint, t::Theme, u, m::Mermaid) = begin
  j = m.joining
  if j !== nothing
    from = part(m, j[1])
    from === nothing && return
    to = landing(m)
    to === nothing || glow!(ctx, paint, t, u, to)
    a, b = point_of(m, from), (j[3], j[4])
    way = towards(a, b)
    if way !== nothing
      long = 0.75u
      pen!(paint, t.accent, 0.12u, :solid)
      Skia.sk_canvas_draw_line(ctx, flt(a[1]), flt(a[2]), flt(b[1] - way[1] * SHORT[:arrow] * long), flt(b[2] - way[2] * SHORT[:arrow] * long), paint)
      tip!(ctx, paint, :arrow, b, way..., long, t.accent, 0.12u, t.surface)
    end
    dot!(ctx, paint, t, u, a, true)
  else
    p = m.hovered
    (p !== nothing && any(q -> q === p, m.made[2].parts)) || return
    # A diagram on its own shows the point only while the mouse is over it. An app that takes the mouse says when it leaves.
    m.keys === nothing && !ishovered(m) && return
    m.typing == (p.kind, p.key) && return
    dot!(ctx, paint, t, u, point_of(m, p), m.on_point)
  end
end

"Draw the point of a part at `at`: a ring in the accent, which fills while the mouse is on it"
dot!(ctx, paint, t::Theme, u, at, lit) = begin
  r = (lit ? 0.38 : 0.3) * u
  fill!(paint, lit ? t.accent : t.surface)
  Skia.sk_canvas_draw_circle(ctx, flt(at[1]), flt(at[2]), flt(r), paint)
  pen!(paint, t.accent, 0.1u, :solid)
  Skia.sk_canvas_draw_circle(ctx, flt(at[1]), flt(at[2]), flt(r), paint)
end

"The place in the picture that's at the place `at` in the window"
spot(m::Mermaid, at) =((Float64(at[1].value) - m.place[1]) / m.place[3], (Float64(at[2].value) - m.place[2]) / m.place[3])

onkey(m::Mermaid, ev::KeyPress{Keys.mouse_left}) = begin
  changes(m) || return nothing
  # On a part's point, the mouse drags a line from the part
  press_at!(m, spot(m, ev.window.mouse)...) && (keyboard!(m); return handled)
  pick_at!(m, spot(m, ev.window.mouse)...)
  # The keys are the diagram's from now on, or the field's while words are typed
  m.typing === nothing && keyboard!(m)
  handled
end
onkey(m::Mermaid, ::KeyPress{K}) where K = key!(m, K) ? handled : nothing
onkey(m::Mermaid, ev::KeyRelease{Keys.mouse_left}) = let_go_at!(m, spot(m, ev.window.mouse)...) ? handled : nothing

# The mouse shows the point of the part that it's over, and a line that's dragged from one follows it
onmouse(m::Mermaid, ev::MouseMove) = begin
  changes(m) || return nothing
  at = spot(m, ev.position)
  m.joining === nothing && return (hover_at!(m, at...); nothing)
  Keys.mouse_left in ev.window.keys ? drag_to!(m, at...) : let_go_at!(m, at...)
  handled
end

# While a tool waits for a click on a part, or a line is dragged from a part's point, the mouse is a cross
cursor(m::Mermaid) = changes(m) && (m.waiting !== nothing || m.joining !== nothing || m.on_point) ? :crosshair : nothing

"""
Make the part that's selected glow: a soft light in the theme's accent. A box,
or another shape, has it outside its edge, which stays as it is. A line has it
all along it.
"""
glow!(ctx, paint, t::Theme, u, p::Part) = begin
  path = Skia.sk_path_new()
  closed = p.shape == :area || isempty(p.path)
  if p.shape == :area
    polygon!(path, p.path)
  elseif isempty(p.path)
    outline!(path, Shape(p.shape, p.box...), u)
  else
    Skia.sk_path_move_to(path, flt(p.path[1][1]), flt(p.path[1][2]))
    foreach(q -> Skia.sk_path_line_to(path, flt(q[1]), flt(q[2])), p.path[2:end])
  end
  light = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(light, true)
  ink = RGBA(convert(RGB{Float64}, t.accent), 0.8)
  closed ? fill!(light, ink) : pen!(light, ink, 0.2u, :solid)
  blur = Skia.sk_maskfilter_new_blur_with_flags(closed ? Skia.SK_BLUR_STYLE_OUTER : Skia.SK_BLUR_STYLE_NORMAL, flt(0.15u), true)
  Skia.sk_paint_set_maskfilter(light, blur)
  Skia.sk_canvas_draw_path(ctx, path, light)
  Skia.sk_maskfilter_unref(blur)
  Skia.sk_paint_delete(light)
  Skia.sk_path_delete(path)
end

"""
Draw the words that are being typed in the part, in place of its own words and
with their look: with the caret after the place that the next character goes
in, and the colour of a selection behind the words that are selected. The
part's glow is all that's round them.
"""
draw_typing(ctx, paint, t::Theme, u, m::Mermaid) = begin
  p = part(m, m.typing)
  p === nothing && return
  f = field!(m)
  w = typed_words(m, p)
  to(n) = wide_to(m, w, n)
  # A click in the words, or in the room that the part's own words had, puts the caret there
  (cx, cy), (rw, rh) = p.words, p.room
  left, right = min(w.x, cx - rw / 2, cx - 1.5u), max(w.x + to(length(w.text)), cx + rw / 2, cx + 1.5u)
  h = max(1.9u, rh + 0.6u)
  m.typed_in = (left - 0.6u, cy - h / 2, right - left + 1.2u, h)
  # Words that are wider than the room of a part that has no box to grow, like a line's label,
  # have the colour that's behind them under them, so that what they cross doesn't show through
  if too_wide(m, p) > 0 && grown(m, p) === nothing
    path = Skia.sk_path_new()
    Skia.sk_path_add_rounded_rect(path, bounds(w.x - 0.3u, cy - 0.75w.size, to(length(w.text)) + 0.6u, 1.5w.size), flt(0.3u), flt(0.3u), Skia.SK_PATH_DIRECTION_CW)
    fill!(paint, behind(m, t, cx, cy))
    Skia.sk_canvas_draw_path(ctx, path, paint)
    Skia.sk_path_delete(path)
  end
  lo, hi = minmax(f.anchor, f.cursor)
  if lo != hi
    fill!(paint, RGBA(convert(RGB{Float64}, t.accent), 0.3))
    Skia.sk_canvas_draw_rect(ctx, bounds(w.x + to(lo), cy - 0.65w.size, to(hi) - to(lo), 1.3w.size), paint)
  end
  isempty(w.text) || show!(ctx, paint, t, u, w)
  # The caret blinks, and it's lit just after a key
  if mod(time() - f.last_action, 1.0) < 0.5
    at = w.x + to(f.cursor)
    pen!(paint, t.accent, 0.12u, :solid)
    Skia.sk_canvas_draw_line(ctx, flt(at), flt(cy - 0.6w.size), flt(at), flt(cy + 0.6w.size), paint)
  end
end

# --- its buttons ------------------------------------------------------------------

"A button over a diagram that can be changed. It uses one of the diagram's tools."
@def mutable struct ToolButton <: SemanticUI
  of::Any = nothing     # the diagram
  tool::Any = nothing   # the Tool that it uses
end

"The buttons for the tools of `m` now, each kept from one frame to the next"
tool_buttons(m::Mermaid) = map(tools(m)) do tool
  b = kept!(() -> ToolButton(of=m), m, (:tool, tool.name))
  getfield(b, :parent) === nothing && setfield!(b, :parent, m)
  b.tool = tool
  b
end

# The tool of a button can change while the button is the same one, so it's described on every frame
describe(b::ToolButton) = begin
  t = theme(b)
  k = scale(t)
  lit = b.of.waiting == b.tool.name
  Box(width(28px * k), height(28px * k), radius(6px * k), Alignment.Center, justify=Alignment.Center,
      background(lit ? t.select : ishovered(b) ? t.hover : t.surface),
    Icon(b.tool.icon, size=15px * k, color=lit ? t.accent : t.dim))
end

cursor(::ToolButton) = :hand

onmouse(b::ToolButton, ev::MouseMove) = begin
  t = theme(b)
  show_tooltip!(ev.window, Box(padding(8px, 6px), Text(b.tool.tip, size=sized(12pt, t), color=RGB(0.94, 0.94, 0.94), wrap=WrapMode.none)), b)
  nothing
end

"Use the tool of the button. A tool with choices shows them in a menu under the button first."
onkey(b::ToolButton, ev::KeyPress{Keys.mouse_left}) = begin
  m, tool = b.of, b.tool
  hide_tooltip!(ev.window)
  if isempty(tool.choices)
    use!(m, tool.name)
  else
    t = theme(b)
    show_menu!(ev.window, [first(c) for c in tool.choices], 0px, 0px, 200px * scale(t); theme=t, under=b, gap=4px,
               onselect=i -> i > 0 && use!(m, tool.name, last(tool.choices[i])))
  end
  m.typing === nothing && keyboard!(m)
  handled
end

export Mermaid, diagram, problem, kind, tools, use!, pick_at!, key!, retype!, settle!, cancel!, part, part_at, changes, pictured, Tool, Part,
       hover_at!, unhover!, press_at!, drag_to!, let_go_at!, landing, point_of

