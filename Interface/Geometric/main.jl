@use "github.com/jkroso/Prospects.jl" @property @abstract @def ["Enum.jl" @Enum] assoc
@use "github.com/jkroso/Font.jl" ["units" pt px]
@use "github.com/jkroso/Units.jl" Length mm
@use "../abstract" GeometricUI mixin! StyleNode Text propertyname
@use Colors: Color, Colorant, RGB, hex

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

@Enum BorderStyle none dotted dashed solid double inset grove ridge outset

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

Radius(r) = Radius(r, r, r, r)
Radius(top, bottom) = Radius(top, top, bottom, bottom)

@Enum GrowType FitContent Grow None

@abstract struct Dimension <: StyleNode
  min::Length=0px
  max::Length=px(Inf)
  preferred::Length=0px
  grow::GrowType=GrowType.FitContent
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
radius(x...) = Radius(x...)
border(width, style, color; between=false) = begin
  Border(BorderSide(parse_length(width),
                    parse_border_style(style),
                    parse_color(color)),
         between=between)
end
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

@abstract struct Container <: GeometricUI
  background::Background=Background()
  border::Border=Border()
  radius::Radius=Radius()
  padding::Padding=Padding()
  width::Width=Width()
  height::Height=Height()
  child_gap::Length=0px
  align::Alignment=Alignment.Center
end

"A box around vertically arranged children"
@def mutable struct Column <: Container end
"A box around horizontally arranged children"
@def mutable struct Row <: Container end
"A box around a single child"
@def mutable struct Box <: Container end

mixin!(old::Border, new::Border) = begin
  Border(top=isempty(new.top) ? old.top : new.top,
         right=isempty(new.right) ? old.right : new.right,
         bottom=isempty(new.bottom) ? old.bottom : new.bottom,
         left=isempty(new.left) ? old.left : new.left,
         between=isempty(new.between) ? old.between : new.between)
end

@property Container.between_width = self.child_gap + self.border.between.width

export padding, background, border, rgb, pt, mm, px, Container, Box, Column, Row, Text, width, height, GrowType, Alignment, radius
