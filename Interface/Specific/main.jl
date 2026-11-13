@use "github.com/jkroso/Prospects.jl" @def @property @field_str Field ["Enum" @Enum]
@use "github.com/jkroso/Font.jl" ["units" Length px absolute]
@use "../Geometric"... Width Height Dimension state!
@use "../abstract" describe ConcreteUI SemanticUI WrapMode laid laid! epoch
@use "../fonts" skia_font weight_name
@use "../image" image_aspect
@use GeometryBasics: Vec2, Vec
@use Colors...
@use "github.com/jkroso/MiniFB.jl"... int
@use "github.com/jkroso/MiniFB.jl/skia" font_metrics SkiaFont
@use Skia

@Enum Axis x y

@def mutable struct ConcreteRect <: ConcreteUI
  top::px=0px
  left::px=0px
  height::px=0px
  width::px=0px
  # How narrow it can get before its content would overflow
  min_width::px=0px
  # Space inside it that its children can't use: its padding, its border and the gaps between its children.
  # It's worked out once, when the rectangle is made, because every pass of the layout asks for it.
  extra_x::px=0px
  extra_y::px=0px
  children::Vector{ConcreteUI}=ConcreteUI[]
  # What the layout gave it and what it came to at each step. A rectangle whose geometry hasn't
  # changed is used again on the next frame, and these say whether what's in it is still right.
  init_x::px=0px            # the room its parent had for it when it was made, across and down
  init_y::px=0px
  rooted::Bool=false        # it's the root of a layout, which starts out as big as the window
  natural_width::px=0px     # its width and height before its siblings were taken into account
  initial_height::px=0px
  fit_width::px=0px         # the width its parent settled on
  fit_height::px=0px        # its height once its content was measured at that width
  final_height::px=0px      # the height its parent settled on
  epoch::Int=0
  reused::Bool=false        # it's from the last layout, and this layout hasn't yet had to redo it
end

@property ConcreteUI.firstchild = self.children[1]
@property ConcreteUI.children = getfield(self, :children)
@property ConcreteRect.origin = Vec2{px}(self.left, self.top)
@property ConcreteRect.size = Vec2{px}(self.width, self.height)
@property ConcreteRect.background_color = self.from.background.color
@property ConcreteRect.corners = begin
  tl = self.origin
  tr = Vec2{px}(tl[1]+self.width, tl[2])
  br = Vec2{px}(tl[1]+self.width, tl[2]+self.height)
  bl = Vec2{px}(tl[1], tl[2]+self.height)
  (tl, tr, br, bl)
end

const polarity = Vec{4,Vec2{Int}}(Vec2(1, 1), Vec2(-1, 1), Vec2(-1, -1), Vec2(1, -1))

@property ConcreteRect.centers = Vec{4,Vec2{px}}((c+r*p for (c,r,p) in zip(self.corners, self.radii, polarity))...)

@property ConcreteRect.border_colors = begin
  b = self.from.border
  (b.top.color, b.right.color, b.bottom.color, b.left.color)
end

@property ConcreteRect.border_widths = begin
  b = self.from.border
  Vec{4,px}(b.top.width, b.right.width, b.bottom.width, b.left.width)
end

@property ConcreteRect.radii = begin
  r = self.from.radius
  Vec{4,px}(r.tl, r.tr, r.br, r.bl)
end

@def mutable struct ConcreteText <: ConcreteUI
  width::px=0px
  height::px=0px
  top::px=0px
  left::px=0px
  lines::Vector{SubString{String}}=Vector[]
  words::Vector{SubString{String}}=Vector[]
  # How wide each word is, measured with the Skia font that draws it
  widths::Vector{px}=px[]
end

@property ConcreteText.size = Vec2{px}(self.width, self.height)

# These print as what they are and where, not as every field of every rectangle around them
Base.show(io::IO, ui::ConcreteRect) =
  print(io, "ConcreteRect of ", ui.from === nothing ? "nothing" : nameof(typeof(ui.from)), ", ", ui.width, " × ", ui.height, " at (", ui.left, ", ", ui.top, ")")
Base.show(io::IO, ui::ConcreteText) =
  print(io, "ConcreteText of ", repr(ui.from.content), ", ", ui.width, " × ", ui.height, " at (", ui.left, ", ", ui.top, ")")

"""
Layout runs in the same order as Clay's:

1. `initialize` builds the concrete tree. Children report their natural widths
   upward, so fit-content containers know how wide their content is. A semantic
   node whose geometry is as it was at the last layout gets its rectangle from
   that layout back. Each later step leaves what's in the rectangle alone if
   it's given the size it was given then, and lays it out afresh if not.
2. `fit_widths!` works down the tree. Each container gives spare width to
   children that grow, takes it from children that can shrink, and resolves
   percentage widths.
3. `fit_heights!` works up the tree. Text wraps to its final width, images
   take their height from their aspect ratio, and fit-content containers
   measure the height of what they now contain.
4. `grow_heights!` works down the tree and shares out spare height.
5. `position!` places each child, using `align` and `justify`.
"""
function describe(ui::Container, (w, h))
  toplevel = ConcreteRect(width=w, height=h)
  cui = initialize(ui, toplevel)
  push!(toplevel.children, cui)
  fit_widths!(ui, cui)
  fit_heights!(ui, cui)
  isgrowable(ui, Axis.y) && (cui.height = clamp(h, minsize(cui, field"height"), maxsize(cui, field"height")))
  grow_heights!(ui, cui)
  # A rectangle that's used again may have been moved since the last layout, as a popup's is
  cui.left = cui.top = 0px
  position!(ui, cui)
  cui
end

field(d::Axis) = d == Axis.x ? field"width" : field"height"
field(ui, d::Axis) = field(d)
dimension(ui::Container, d::Axis) = getproperty(ui, field(d))

"The axes along which a container lays its children end to end"
main_axes(::Row) = (Axis.x,)
main_axes(::Column) = (Axis.y,)
main_axes(::Union{Box,Wedge}) = (Axis.x, Axis.y)
main_axes(::Container) = ()

"Space inside a container that its children can't use along one axis"
extra(cui::ConcreteRect, axis::Axis) = axis == Axis.x ? cui.extra_x : cui.extra_y
extra(::ConcreteText, ::Axis) = 0px

# A length is nearly always in px already, and then there's nothing to convert
inpx(x::px) = x
inpx(x) = convert(px, x)

"Start a container's `extra` with its padding and border"
function measure_extra!(rect::ConcreteRect, ui::Container)
  (;padding, border) = ui
  rect.extra_x = inpx(padding.left) + inpx(padding.right) + inpx(border.left.width) + inpx(border.right.width)
  rect.extra_y = inpx(padding.top) + inpx(padding.bottom) + inpx(border.top.width) + inpx(border.bottom.width)
  rect
end

"Add the gaps between a container's children to its `extra`, along its layout direction. Each gap includes any border drawn in it."
function measure_gaps!(rect::ConcreteRect, ui::Container)
  length(rect.children) > 1 || return rect
  gaps = (inpx(ui.child_gap) + inpx(ui.border.between.width)) * (length(rect.children) - 1)
  axes = main_axes(ui)
  Axis.x in axes && (rect.extra_x += gaps)
  Axis.y in axes && (rect.extra_y += gaps)
  rect
end

"Space a container has for its children along one axis"
inner(cui::ConcreteRect, axis::Axis) = getproperty(cui, field(axis)) - extra(cui, axis)

extra_width(ui::ConcreteUI) = extra(ui, Axis.x)
extra_height(ui::ConcreteUI) = extra(ui, Axis.y)
"compute the width inside an element available for it's children to occupy"
internalwidth(ui::ConcreteUI) = inner(ui, Axis.x)
internalheight(::Nothing) = 0px
internalheight(ui::ConcreteUI) = inner(ui, Axis.y)

"True when a dimension doesn't depend on the parent: it measures its content"
fits_content(d::Dimension) = d.preferred == 0px && d.percent == 0 && d.grow != GrowType.Grow
"True when a dimension starts at its content size and then takes spare space"
grows_from_content(d::Dimension) = d.preferred == 0px && d.percent == 0 && d.grow == GrowType.Grow

"The first guess at an element's size, before its siblings are taken into account. `room` is the space its parent has for it."
initial_size(d::Dimension, room::px) = begin
  size = if d.preferred != 0px
    d.preferred
  elseif d.percent > 0
    room * d.percent
  else
    room
  end
  clamp(convert(px, size), d.min, d.max)
end

"The initial pass creates the new tree and sets the width of all nodes to their natural value"
function initialize(ui::Container, parent::ConcreteRect)
  x, y, rooted = inner(parent, Axis.x), inner(parent, Axis.y), parent.from === nothing
  rect = kept(ui, x, y, rooted)
  if rect !== nothing
    # Nothing in this geometry has changed, so start from the rectangle the last layout made for it
    setfield!(rect, :parent, parent)
    rect.width, rect.height, rect.reused = rect.natural_width, rect.initial_height, true
    return rect
  end
  rect = build!(ConcreteRect(from=ui, parent=parent), ui, x, y, rooted)
  source = ui.from
  source isa SemanticUI && laid!(source, rect)
  rect
end

"The rectangle the last layout made for `ui`, if `ui` hasn't changed since and its parent has the same room for it"
kept(ui::Container, x::px, y::px, rooted::Bool) = begin
  source = ui.from
  source isa SemanticUI || return nothing
  rect = laid(source)
  rect isa ConcreteRect && rect.from === ui && rect.epoch == epoch[] && rect.init_x == x && rect.init_y == y &&
    rect.rooted == rooted ? rect : nothing
end

"""
Give `rect` its natural size and make the rectangles in it. `x` and `y` are the
room its parent has for it. A layout does this to a new rectangle, and again to
one from the last layout that turns out to be given another size than it was.
"""
function build!(rect::ConcreteRect, ui::Container, x::px, y::px, rooted::Bool)
  rect.init_x, rect.init_y, rect.rooted, rect.epoch, rect.reused = x, y, rooted, epoch[], false
  rect.width = initial_size(ui.width, x)
  rect.height = initial_size(ui.height, y)
  # Children take their first size from the room inside it, before the gaps between them are known
  measure_extra!(rect, ui)
  rect.children = ConcreteUI[initialize(child, rect) for child in ui.children]
  measure_gaps!(rect, ui)
  # Like Clay, growing elements start at their content size and grow from
  # there. The root is the exception: it starts out as big as the window.
  if fits_content(ui.width) || (grows_from_content(ui.width) && !rooted)
    content = content_width(ui, rect)
    if content !== nothing
      rect.width = clamp(content, ui.width.min, ui.width.max)
    elseif !fits_content(ui.width)
      rect.width = clamp(0px, ui.width.min, ui.width.max)
    end
  end
  # Something that never shrinks is as narrow as it can get already
  rect.min_width = ui.width.grow == GrowType.None ? rect.width :
                   max(convert(px, ui.width.min), content_min_width(ui, rect))
  rect.natural_width, rect.initial_height = rect.width, rect.height
  rect
end

"How narrow a container's content can get without overflowing"
content_min_width(ui::Container, rect) = clips(ui) ? extra(rect, Axis.x) : _content_min_width(ui, rect)
"True when a container hides content that doesn't fit, so it can be narrower than it"
clips(ui::Container) = ui.clip || ui.clip_x || ui isa Scroll
_content_min_width(::Row, rect) = sum(c -> minsize(c, field"width"), rect.children, init=0px) + extra(rect, Axis.x)
_content_min_width(::Union{Box,Wedge,Stack,Column,Scroll}, rect) =
  maximum(c -> minsize(c, field"width"), rect.children, init=0px) + extra(rect, Axis.x)
_content_min_width(::Container, rect) = 0px

"How wide a container's content is, or `nothing` if the content doesn't say"
content_width(::Row, rect) = sum(field"width", rect.children, init=0px) + extra(rect, Axis.x)
content_width(::Union{Box,Wedge,Stack,Column,Scroll}, rect) = maximum(field"width", rect.children, init=0px) + extra(rect, Axis.x)
content_width(::Container, rect) = nothing
content_width(img::Image, rect) = begin
  img.height.preferred == 0px && return nothing
  img.height.preferred * aspect(img)
end

"How tall a container's content is"
content_height(::Column, rect) = sum(field"height", rect.children, init=0px) + extra(rect, Axis.y)
content_height(::Container, rect) = maximum(field"height", rect.children, init=0px) + extra(rect, Axis.y)
content_height(img::Image, rect) = rect.width / aspect(img)

aspect(img::Image) = img.aspect > 0 ? img.aspect : isempty(img.src) ? 1.0 : image_aspect(img.src)

isgrowable(ui, d::Axis) = isgrowable(ui, field(ui, d))
isgrowable(ui::ConcreteUI, f::Field) = isgrowable(ui.from, f)
isgrowable(ui::Container, f::Field) = getproperty(ui, f).grow == GrowType.Grow
isgrowable(ui::Union{ConcreteText,Text}, f::Field) = true
# Text is exactly as tall as the lines it wraps into
isgrowable(ui::Union{ConcreteText,Text}, ::Field{:height}) = false
isshrinkable(ui, d::Axis) = isshrinkable(ui, field(ui, d))
isshrinkable(ui::ConcreteUI, f::Field) = isshrinkable(ui.from, f)
isshrinkable(ui::Container, f::Field) = begin
  d = getproperty(ui, f)
  d.grow != GrowType.None && d.percent == 0
end
isshrinkable(ui::Union{ConcreteText,Text}, ::Field{:width}) = true
# Wrapped text can't get any shorter than the lines it was wrapped into
isshrinkable(ui::Union{ConcreteText,Text}, ::Field{:height}) = false

# Leftover space smaller than this counts as none. Without it, repeatedly
# sharing a tiny floating point remainder can loop forever.
const slack = 0.01px

"Distribute the excess width accross all elements that can accept it"
function grow!(ui::ConcreteRect, direction::Axis)
  prop = field(ui, direction)
  remainder = remaining_size(ui, prop)
  remainder > slack || return remainder
  growable = sort!(filter(ui->isgrowable(ui, prop), ui.children), by=prop)
  while !isempty(growable) && remainder > slack
    smallest, next_smallest = best(growable, by=prop)
    diff = next_smallest == 0px ? remainder/length(smallest) : next_smallest - getproperty(smallest[1], prop)
    togrow = min(remainder/length(smallest), diff)
    for child in smallest
      size = getproperty(child, prop) + togrow
      setproperty!(child, prop, size)
      remainder -= togrow
      size = getproperty(child, prop)
      m = maxsize(child, prop)
      if m <= size # When an item has reached it's max size it's no longer growable
        deleteat!(growable, findfirst(==(child), growable))
        setproperty!(child, prop, m)
        remainder += (size - m) # correct for over subtraction
      end
    end
  end
  remainder
end

function shrink!(ui::ConcreteRect, remainder::Length, direction::Axis)
  prop = field(ui, direction)
  remainder < -slack || return remainder
  shrinkable = sort!(filter(ui->isshrinkable(ui, prop), ui.children), by=prop, rev=true)
  while !isempty(shrinkable) && remainder < -slack
    biggest, next_biggest = best(shrinkable, by=prop, comp=isless)
    diff = next_biggest == 0px ? remainder/length(biggest) : next_biggest - getproperty(biggest[1], prop)
    toshrink = max(remainder/length(biggest), diff)
    for child in biggest
      size = getproperty(child, prop)
      setproperty!(child, prop,  size + toshrink)
      remainder -= toshrink
      size = getproperty(child, prop)
      min = minsize(child, prop)
      # When an item has reached it's min size it's no longer shrinkable
      if size <= min
        deleteat!(shrinkable, findfirst(==(child), shrinkable))
        setproperty!(child, prop, convert(px, min))
        remainder += (size - min) # correct for over subtraction
      end
    end
  end
  remainder
end

remaining_size(ui::ConcreteRect, f::Field{:height}) = internalheight(ui) - sum(f, ui.children, init=0px)
remaining_size(ui::ConcreteRect, f::Field{:width}) = internalwidth(ui) - sum(f, ui.children, init=0px)

"Size children that ask for a percentage of this container"
function resolve_percent!(cui::ConcreteRect, axis::Axis)
  available = inner(cui, axis)
  prop = field(axis)
  for child in cui.children
    child isa ConcreteRect || continue
    d = dimension(child.from, axis)
    d.percent > 0 || continue
    setproperty!(child, prop, clamp(convert(px, available * d.percent), d.min, d.max))
  end
end

"""
Size children across the layout direction. Children that grow fill the space,
and children sized by their content are clamped to it, which is what makes long
text wrap inside a narrow Column. Children with a fixed size keep it.
"""
function cross_fit!(cui::ConcreteRect, axis::Axis)
  prop = field(axis)
  available = inner(cui, axis)
  for child in cui.children
    if isgrowable(child, axis)
      setproperty!(child, prop, clamp(available, minsize(child, prop), maxsize(child, prop)))
    elseif axis == Axis.x && width_fits_content(child) && child.width > available
      child.width = max(available, convert(px, minsize(child, prop)))
    end
  end
end

"True when an element's width is the width of its content"
width_fits_content(child::ConcreteRect) = width_fits_content(child.from)
width_fits_content(ui::Container) = fits_content(ui.width)
width_fits_content(_) = false

"Settle the width of every child, working down from the root"
fit_widths!(::Text, ::ConcreteText) = nothing
function fit_widths!(ui::Container, cui::ConcreteRect)
  if cui.reused
    # It's as wide as it was at the last layout, so everything in it is too
    cui.width == cui.fit_width && return
    width = cui.width
    build!(cui, ui, cui.init_x, cui.init_y, cui.rooted)
    cui.width = width
  end
  cui.fit_width = cui.width
  resolve_percent!(cui, Axis.x)
  if Axis.x in main_axes(ui) || ui isa Scroll
    shrink!(cui, grow!(cui, Axis.x), Axis.x)
  else
    cross_fit!(cui, Axis.x)
  end
  for child in cui.children
    fit_widths!(child.from, child)
  end
end

"Measure every element's height now its width is known, working up from the leaves"
function fit_heights!(ui::Container, cui::ConcreteRect)
  # Used again at the same width, it's as tall as its content made it last time
  cui.reused && return (cui.height = cui.fit_height; nothing)
  for child in cui.children
    fit_heights!(child.from, child)
  end
  d = ui.height
  if d.preferred != 0px
    cui.height = clamp(convert(px, d.preferred), d.min, d.max)
  elseif d.percent == 0
    cui.height = clamp(content_height(ui, cui), d.min, d.max)
  end
  cui.fit_height = cui.height
  nothing
end

# The width of the text element should already of been allocated so here we just wrap the text
# and set the height accordingly
function fit_heights!(from::Text, ui::ConcreteText)
  ui.lines = wraplines(from, ui)
  # Height tracks visible glyph bounds, NOT the font's full line box.
  # A single line is exactly cap_height tall — placing the baseline at the box
  # bottom — so wrapping a Text in a centred Box visually centres the cap area
  # of digits and capitals. Descenders (g, y, p) extend below the box; for
  # multi-line text we add full lineheight per extra line so descenders of one
  # line never collide with caps of the next.
  # We use Skia's actual `capHeight` (varies by font, ~0.72–0.79 × em) instead
  # of Font.jl's 0.72 approximation so the reserved height matches what the
  # renderer will actually draw — otherwise glyphs appear high in their box.
  caph = skia_cap_height(from)
  leading = absolute(from.lineheight, from.size)
  ui.height = caph + convert(px, (length(ui.lines) - 1) * leading)
  nothing
end

wraplines(from::Text, ui::ConcreteText) = begin
  if from.wrap == WrapMode.none || isempty(ui.words)
    SubString{String}[SubString(from.content)]
  elseif from.wrap == WrapMode.newlines
    split(from.content, '\n')
  else
    wraptext(from.content, ui.width, ui.words, ui.widths, text_width(from, " "))
  end
end

"Share out spare height, working down from the root"
grow_heights!(::Text, ::ConcreteText) = nothing
function grow_heights!(ui::Container, cui::ConcreteRect)
  if cui.reused
    cui.reused = false
    # It's as tall as it was at the last layout, so everything in it is too
    cui.height == cui.final_height && return
    width, height = cui.width, cui.height
    build!(cui, ui, cui.init_x, cui.init_y, cui.rooted)
    cui.width = width
    fit_widths!(ui, cui)
    fit_heights!(ui, cui)
    cui.height = height
  end
  cui.final_height = cui.height
  resolve_percent!(cui, Axis.y)
  if Axis.y in main_axes(ui)
    shrink!(cui, grow!(cui, Axis.y), Axis.y)
  elseif ui isa Scroll
    # Content scrolls rather than shrinks. Content that grows still fills
    # the viewport when it's shorter than it.
    for child in cui.children
      isgrowable(child, Axis.y) && (child.height = max(child.height, inner(cui, Axis.y)))
    end
  else
    cross_fit!(cui, Axis.y)
  end
  for child in cui.children
    grow_heights!(child.from, child)
  end
end

minsize(ui::Container, prop::Field) = getproperty(ui, prop).min
minsize(ui::ConcreteUI, prop::Field) = minsize(ui.from, prop)
minsize(ui::ConcreteRect, ::Field{:width}) = ui.min_width
minsize(ui::ConcreteText, ::Field{:width}) =
  ui.from.wrap == WrapMode.words ?
    maximum(ui.widths, init=0px) :
    natural_width(ui.from)
minsize(ui::ConcreteText, ::Field{:height}) = ui.height

maxsize(ui::Container, prop::Field) = max(getproperty(ui, prop).preferred, getproperty(ui, prop).max)
maxsize(ui::ConcreteText, ::Field{:height}) = ui.height
maxsize(ui::ConcreteText, ::Field{:width}) = px(Inf)
maxsize(ui::ConcreteUI, prop::Field) = maxsize(ui.from, prop)

function best(growable; by=field"width", comp=(>))
  first = growable[1]
  smallest_val = getproperty(first, by)
  group = eltype(growable)[first]
  for next in @view(growable[2:end])
    next_val = getproperty(next, by)
    comp(next_val, smallest_val) && return group, next_val
    push!(group, next)
  end
  group, 0px
end

"""
How wide `s` is when drawn in `t`'s font. Layout measures with the same Skia
font that draws the text, so the two always agree. Measuring the font file
directly can't, for fonts like the macOS system font that the system adjusts
for each size.
"""
text_width(t::Text, s::AbstractString) = text_width(font(t), s)
text_width(f::SkiaFont, s::Union{String,SubString{String}}) =
  px(Skia.sk_font_measure_text(f.raw, pointer(s), UInt64(ncodeunits(s)), Skia.SK_TEXT_ENCODING_UTF8, C_NULL, C_NULL))
text_width(f::SkiaFont, s::AbstractString) = text_width(f, String(s))

"The Skia font that measures and draws `t`"
font(t::Text) = skia_font(t.family, t.size, style(t))

"The name of the style `t` is drawn in: its `subfamily`, or without one the name of its `weight`, like \"Bold\" for 700"
style(t::Text) = !isempty(t.subfamily) || t.weight == 400 ? t.subfamily : weight_name(t.weight)

function initialize(ui::Text, parent)
  words = split(ui.content)
  f = font(ui)
  widths = px[text_width(f, w) for w in words]
  # Text that wraps at words is as wide as `wraptext` counts it: a word and a
  # space at a time. The whole line measured at once can be narrower, because
  # of kerning, and then text in a box made to fit it would wrap its last word.
  natural = ui.wrap == WrapMode.words && !isempty(words) ? words_width(widths, text_width(f, " ")) : natural_width(ui)
  ConcreteText(from=ui,
               width=natural,
               height=cap_height(f),  # natural height = visible glyph height (single line)
               words=words,
               widths=widths,
               parent=parent)
end

"How wide words are on one line with a space between each, added up the way `wraptext` adds them"
words_width(widths, space_width) = begin
  w = widths[1]
  for width in @view widths[2:end]
    w += space_width + width
  end
  w
end

natural_width(ui::Text) =
  ui.wrap == WrapMode.newlines ?
    maximum(line -> text_width(ui, line), split(ui.content, '\n'), init=0px) :
    text_width(ui, ui.content)

"Skia's own height of a capital letter in a font, in px. It's looked up once for each font."
const cap_heights = IdDict{SkiaFont,px}()
cap_height(f::SkiaFont) = get!(() -> px(font_metrics(f).capHeight), cap_heights, f)::px
skia_cap_height(t::Text) = cap_height(font(t))

"Break `s` into lines no wider than `limit`, given the width of each of its words"
function wraptext(s::String, limit::px, words, widths, space_width::px)
  isempty(words) && return SubString{String}[SubString(s)]
  lines = SubString{String}[]
  pairs = zip(widths, words)
  w, lastword = first(pairs)
  offset = 1
  for (width, word) in Iterators.drop(pairs, 1)
    w += space_width + width
    if w > limit
      push!(lines, @view s[offset:prevind(s, word.offset)])
      lastword = word
      offset = nextind(s, word.offset)
      w = width
    else
      lastword = word
    end
  end
  offset > lastindex(s) && return lines
  push!(lines, @view s[offset:end])
end

# Visual translation offset baked onto Container nodes (animations, etc.).
# Applied to each child immediately before recursing into its position!,
# so the offset propagates through the whole subtree without affecting
# how siblings flow.
apply_translate!(child::ConcreteRect) = translate!(child.from, child)
apply_translate!(_::ConcreteUI) = nothing
translate!(c::Container, child) = begin
  child.left += c.offset_x
  child.top  += c.offset_y
end
translate!(_, child) = nothing

function position!(::Text, ui::ConcreteText) end

"Where content of size `content` starts inside `space` that begins at `start`"
place(start, space, content, a::Alignment) = begin
  offset = a == Alignment.Center ? (space - content)/2 :
           a == Alignment.End    ? space - content :
                                   0px
  # Snap tiny offsets so rounding doesn't leave hairline gaps at the edge
  isapprox(int(start), int(start + offset), atol=1) ? start : start + offset
end

"The top left corner of a container's content area"
content_origin((;padding, border)::Container, ui::ConcreteRect) =
  (ui.left + padding.left + border.left.width, ui.top + padding.top + border.top.width)

function position!(scroll::Scroll, ui::ConcreteRect)
  isempty(ui.children) && return
  child = ui.children[1]
  left, top = content_origin(scroll, ui)
  state = state!(scroll)
  state.content_height = child.height + extra(ui, Axis.y)
  state.viewport = inner(ui, Axis.y)
  state.offset = clamp(state.offset, 0px, max(0px, state.content_height - ui.height))
  child.left = left
  child.top = top - state.offset
  apply_translate!(child)
  position!(child.from, child)
end

function position!(box::Union{Box,Wedge}, ui::ConcreteRect)
  isempty(ui.children) && return
  child = ui.children[1]
  left, top = content_origin(box, ui)
  child.top = place(top, inner(ui, Axis.y), child.height, box.align)
  child.left = place(left, inner(ui, Axis.x), child.width, box.align)
  apply_translate!(child)
  position!(child.from, child)
end

function position!(row::Row, ui::ConcreteRect)
  left, top = content_origin(row, ui)
  h = inner(ui, Axis.y)
  used = sum(field"width", ui.children, init=0px)
  left = place(left, inner(ui, Axis.x), used, row.justify)
  for child in ui.children
    child.top = place(top, h, child.height, row.align)
    child.left = left
    left += child.width + row.between_width
    apply_translate!(child)
    position!(child.from, child)
  end
end

function position!(col::Column, ui::ConcreteRect)
  left, top = content_origin(col, ui)
  w = inner(ui, Axis.x)
  used = sum(field"height", ui.children, init=0px)
  top = place(top, inner(ui, Axis.y), used, col.justify)
  for child in ui.children
    child.left = place(left, w, child.width, col.align)
    child.top = top
    top += child.height + col.between_width
    apply_translate!(child)
    position!(child.from, child)
  end
end

function position!(stack::Stack, ui::ConcreteRect)
  left, top = content_origin(stack, ui)
  for child in ui.children
    child.top = place(top, inner(ui, Axis.y), child.height, stack.align)
    child.left = place(left, inner(ui, Axis.x), child.width, stack.align)
    apply_translate!(child)
    position!(child.from, child)
  end
end

position!(::Container, ::ConcreteRect) = nothing

export describe, ConcreteText, ConcreteRect, font
