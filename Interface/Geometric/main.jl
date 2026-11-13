@use "github.com/jkroso/Prospects.jl" @property @abstract @def ["Enum.jl" @Enum] assoc Field
@use "github.com/jkroso/Font.jl" ["units" pt px]
@use "github.com/jkroso/Units.jl" Length mm
@use "../abstract" GeometricUI SemanticUI mixin! StyleNode Text TextAlign propertyname remember! kept!
@use Colors: Color, Colorant, RGB, RGBA, hex, alpha

const transparent = parse(Colorant, "transparent")
const black = parse(Colorant, "black")

@def struct Padding <: StyleNode
  top::Length=0px
  right::Length=0px
  bottom::Length=0px
  left::Length=0px
end

@property Padding.width = self.left + self.right
@property Padding.height = self.bottom + self.top

"How a border's line is drawn. A `double` one is two lines, each a third of the border's width."
@Enum BorderStyle none dotted dashed solid double

@def struct BorderSide <: StyleNode
  width::Length=0mm
  style::BorderStyle=BorderStyle.none
  color::Colorant=black
end

abstract type StyleGroup <: StyleNode end

@def struct Border <: StyleGroup
  top::BorderSide=BorderSide()
  right::BorderSide=BorderSide()
  bottom::BorderSide=BorderSide()
  left::BorderSide=BorderSide()
  between::BorderSide=BorderSide()
end

@property Border.width = self.left.width + self.right.width
@property Border.height = self.top.width + self.bottom.width
Base.isempty(b::BorderSide) = b.width == 0px || b.style == BorderStyle.none
Base.isempty(b::Border) = all(isempty, values(b))
Base.values(b::Border) = (b.top, b.right, b.bottom, b.left)

Border(v::BorderSide; between=false) = Border(v, v, v, v, between ? v : BorderSide())
Border(a::BorderSide, b::BorderSide) = Border(a, b, a, b, BorderSide())

@def struct Radius <: StyleNode
  tl::Length=0px
  tr::Length=0px
  br::Length=0px
  bl::Length=0px
end

# `radius(8px)` rounds every corner. `radius(8px, 0px)` rounds the two at the top and
# leaves the two at the bottom square. `radius(tl, tr, br, bl)` sets each one.
Radius(r) = Radius(r, r, r, r)
Radius(top, bottom) = Radius(top, top, bottom, bottom)

@Enum GrowType FitContent Grow None

"""
Sizing along one axis. `preferred` fixes the size, `grow` lets it absorb spare
space and `percent` (0–1) takes that fraction of the parent's inner size after
padding and gaps. `min` and `max` clamp whichever of these applies.
"""
@abstract struct Dimension <: StyleNode
  min::Length=0px
  max::Length=px(Inf)
  preferred::Length=0px
  grow::GrowType=GrowType.FitContent
  percent::Float64=0.0
end
@def Width <: Dimension
@def Height <: Dimension

Width(value) = Width(preferred=value)
Width(min, max) = Width(min=min, max=max)
Height(value) = Height(preferred=value)
Height(min, max) = Height(min=min, max=max)

@def struct Background <: StyleNode
  color::Colorant=transparent
end

"""
A shadow that a container casts on what's behind it. The shadow has the
container's shape and corner radius. `x` and `y` move it right and down, `blur`
softens its edge and `spread` makes it bigger on every side. None of it shows
through the container, even if the container's background is see-through.
A container that clips its children cuts off their shadows at its edges.
"""
@def struct Shadow <: StyleNode
  x::Length=0px
  y::Length=0px
  blur::Length=0px
  spread::Length=0px
  color::Colorant=transparent
end

Base.isempty(s::Shadow) = alpha(s.color) == 0

@Enum KeyPoint tl tc tr cl center cr bl bc br

@def struct RelativePosition <: StyleNode
  parent::KeyPoint=KeyPoint.tl
  self::KeyPoint=KeyPoint.tl
end

@def struct Offset <: StyleNode
  x::Length=0mm
  y::Length=0mm
end

padding(x, y) = Padding(top=y,bottom=y,left=x,right=x)
padding(x) = Padding(x, x, x, x)
padding(t, r, b, l) = Padding(t, r, b, l)
radius(x...) = Radius(x...)
border(width, style, color; between=false) = begin
  Border(BorderSide(parse_length(width),
                    parse_border_style(style),
                    parse_color(color)),
         between=between)
end
"""
`shadow(0, 4, 12)` casts a soft shadow 4px below a container. The arguments are
how far it moves right and down, then how much it blurs. They're in the order
that CSS's `box-shadow` has them.
"""
shadow(x, y, blur=0px, color=RGBA(0, 0, 0, 0.25); spread=0px) =
  Shadow(parse_length(x), parse_length(y), parse_length(blur), parse_length(spread), parse_color(color))
width(args...; kwargs...) = Width(args..., ; kwargs...)
height(args...; kwargs...) = Height(args...; kwargs...)

# enable property filtering on things like borders. So you can do border(1, :solid, "red")[:top]
Base.getindex(b::T, keys::Symbol...) where T<:StyleGroup = begin
  reduce(keys, init=T()) do out, key
    assoc(out, key, getproperty(b, key))
  end
end

parse_border_style(s::Symbol) = getproperty(BorderStyle, s)
parse_color(s::AbstractString) = parse(Colorant, s)
parse_color(c::Colorant) = c
parse_length(i::Int) = px(i)
parse_length(i) = i
background(s) = Background(parse_color(s))
rgb(r=0, g=0, b=0) = RGB(clamp(r/255,0,1),clamp(g/255,0,1),clamp(b/255,0,1))

@Enum Alignment Start Center End

"""
`align` places children across the layout direction (vertically in a Row,
horizontally in a Column, both ways in a Box). `justify` places the whole run of
children along the layout direction, when they don't fill it. With `clip` set,
children are cut off at the container's edges, and content that can't shrink
any further no longer forces the container (and its parents) to be wider.
`clip_x` cuts children off at the left and right edges only. Text is a little
taller than its box, so this keeps the tails of its letters.
`name` only labels the container in the layout inspector.
"""
@abstract struct Container <: GeometricUI
  background::Background=Background()
  border::Border=Border()
  radius::Radius=Radius()
  shadow::Shadow=Shadow()
  padding::Padding=Padding()
  width::Width=Width()
  height::Height=Height()
  child_gap::Length=0px
  align::Alignment=Alignment.Center
  justify::Alignment=Alignment.Start
  clip::Bool=false
  clip_x::Bool=false
  offset_x::px=0px
  offset_y::px=0px
  name::String=""
end

"A box around vertically arranged children"
@def mutable struct Column <: Container end
"A box around horizontally arranged children"
@def mutable struct Row <: Container end
"A box around a single child"
@def mutable struct Box <: Container end
"""
Children placed on top of each other. Each one is sized and aligned against the
whole Stack, and later children draw over earlier ones and get the first click.
Use it to float a panel, like a dialog, over the rest of a layout.
"""
@def mutable struct Stack <: Container end

@Enum ScrollbarMode hover always never

"What a Scroll remembers from one frame to the next"
@def mutable struct ScrollState
  offset::px=0px           # how far it has scrolled
  content_height::px=0px   # how tall its content was in the last layout
  viewport::px=0px         # how much of that it showed
  hover::Bool=false        # the cursor is in it
  thumb_hover::Bool=false  # the cursor is on its scrollbar's thumb
  dragging::Bool=false     # the thumb is being dragged
end

"""
Vertical scroll viewport. Sizes itself like a Box in the cross axis but
lays its single child out at its natural height in the scroll axis,
translating it by `offset` at position-time.

A `describe` can make a new Scroll on each frame. The node being described
remembers how far it has scrolled, so it stays where it was:

    describe(list::FileList) = Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow), rows(list))

If one `describe` makes several Scrolls and their order can change, give each a
`key`, e.g. `Scroll(key=:files)`, so that each gets its own place back. Read
`scroll.offset`, `scroll.content_height` and `scroll.viewport` after it has been
laid out. A Scroll that you keep and put back with `reuse!` still works, and
it's the one to use when a `describe` has to read the offset.

The scrollbar thumb can be dragged. `scrollbar` says when it shows:
`hover` (only while the cursor is inside), `always` or `never`.
`scrollbar_inset` is the gap between the scrollbar and the Scroll's right
edge. Make it 0px to put the scrollbar against the edge of a window.
"""
@def mutable struct Scroll <: Container
  scrollbar::ScrollbarMode=ScrollbarMode.hover
  scrollbar_width::px=6px
  scrollbar_inset::px=4px
  scrollbar_color::Colorant=RGBA(0, 0, 0, 0.38)
  scrollbar_track::Colorant=RGBA(0, 0, 0, 0.06)
  key::Any=nothing
  state::Union{Nothing,ScrollState}=nothing
end

"What `s` remembers. A Scroll that hasn't been given a state yet gets one of its own."
state!(s::Scroll) = begin
  state = getfield(s, :state)
  state === nothing ? setfield!(s, :state, ScrollState()) : state
end

# `scroll.offset` and the rest read and write what the Scroll remembers
const blank = ScrollState()
for name in fieldnames(ScrollState)
  @eval Base.getproperty(s::Scroll, ::Field{$(QuoteNode(name))}) = getfield(something(getfield(s, :state), blank), $(QuoteNode(name)))
  @eval Base.setproperty!(s::Scroll, ::Field{$(QuoteNode(name))}, x) = setproperty!(state!(s), $(QuoteNode(name)), x)
end

# A Scroll that a `describe` made gets back what the node being described kept for it
remember!(owner::SemanticUI, s::Scroll, count) = begin
  n = count[] += 1
  getfield(s, :state) === nothing || return   # the app keeps this Scroll itself, so it has its state already
  setfield!(s, :state, kept!(ScrollState, owner, (Scroll, something(s.key, n))))
  nothing
end

"""
Scroll the shortest distance that shows the content from `top` to `bottom`,
both measured from the top of the content. It needs one layout first, to learn
how tall the Scroll is.
"""
scroll_into_view!(s::Scroll, top, bottom) = begin
  s.viewport > 0px || return s
  if top < s.offset
    s.offset = top
  elseif bottom > s.offset + s.viewport
    s.offset = bottom - s.viewport
  end
  s
end

"""
A raster image (PNG, JPEG, WebP…) drawn to fill its box. If you fix only the
width, the height follows the image's aspect ratio. `aspect` is width ÷ height,
and the default of 0 means "read it from the file".
"""
@def mutable struct Image <: Container
  src::String=""
  aspect::Float64=0.0
end
Image(src::AbstractString, args...; kwargs...) = Image(args...; src=String(src), kwargs...)

"""
A slice of a ring, like a piece of a pie chart or a sunburst, filled with its
`background` colour. It's centred in its box. `inner` and `outer` are its radii,
as fractions of the radius of the biggest circle that fits in the box, so the
slice grows with the box. `start` and `sweep` are angles in degrees, clockwise
from 12 o'clock. A `border` outlines the slice, centred on its edge. Its
children are placed as in a Box. Only the slice itself gets the cursor, so
wedges stacked in one box can each be hovered and clicked.
"""
@def mutable struct Wedge <: Container
  inner::Float64=0.0
  outer::Float64=1.0
  start::Float64=0.0
  sweep::Float64=360.0
end

mixin!(r::Container, a::Alignment) = (r.align = a; r)

mixin!(old::Border, new::Border) = begin
  Border(top=isempty(new.top) ? old.top : new.top,
         right=isempty(new.right) ? old.right : new.right,
         bottom=isempty(new.bottom) ? old.bottom : new.bottom,
         left=isempty(new.left) ? old.left : new.left,
         between=isempty(new.between) ? old.between : new.between)
end

@property Container.between_width = self.child_gap + self.border.between.width

export padding, background, border, shadow, Shadow, BorderSide, BorderStyle, Radius, rgb, pt, mm, px, Container, Box, Stack, Column, Row, Scroll, ScrollbarMode, scroll_into_view!, Image, Wedge, Text, TextAlign, width, height, GrowType, Alignment, radius
