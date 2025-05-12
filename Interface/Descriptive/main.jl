@use "github.com/jkroso/Prospects.jl" @property @abstract @def ["Enum.jl" @Enum] assoc
@use "github.com/jkroso/Font.jl" ["units" pt px]
@use "github.com/jkroso/Units.jl" Length mm
@use "../abstract" DescriptiveUI mixin! StyleNode Text propertyname
@use Colors: Color, Colorant, RGB, hex

const transparent = parse(Colorant, "transparent")
const black = parse(Colorant, "black")

@def struct Padding <: StyleNode
  top::Union{Missing,Length}=missing
  right::Union{Missing,Length}=missing
  bottom::Union{Missing,Length}=missing
  left::Union{Missing,Length}=missing
end

@property Padding.width = +(ismissing(self.left) ? 0px : self.left, ismissing(self.right) ? 0px : self.right)
@property Padding.height = +(ismissing(self.top) ? 0px : self.top, ismissing(self.bottom) ? 0px : self.bottom)

@Enum BorderStyle none dotted dashed solid double inset grove ridge outset

@def struct BorderSide <: StyleNode
  width::Length=0mm
  style::BorderStyle=BorderStyle.none
  color::Colorant=black
end

abstract type StyleGroup <: StyleNode end

@def struct Border <: StyleGroup
  top::Union{BorderSide,Missing}=missing
  right::Union{BorderSide,Missing}=missing
  bottom::Union{BorderSide,Missing}=missing
  left::Union{BorderSide,Missing}=missing
  between_children::Union{BorderSide,Missing}=missing
end

@property Border.width = +(ismissing(self.left) ? 0px : self.left.width, ismissing(self.right) ? 0px : self.right.width)
@property Border.height = +(ismissing(self.top) ? 0px : self.top.width, ismissing(self.bottom) ? 0px : self.bottom.width)
Base.isempty(b::Border) = all(ismissing, values(b))
Base.values(b::Border) = (b.top, b.right, b.bottom, b.left)

Border(v::BorderSide; between_children=false) = Border(v, v, v, v, between_children ? v : missing)
Border(a::BorderSide, b::BorderSide) = Border(a, b, a, b, missing)

@def struct Radius <: StyleNode
  tl::Union{Missing,Length}=missing
  tr::Union{Missing,Length}=missing
  br::Union{Missing,Length}=missing
  bl::Union{Missing,Length}=missing
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
border(width, style, color; between_children=false) = begin
  Border(BorderSide(parse_length(width),
                    parse_border_style(style),
                    parse_color(color)),
         between_children=between_children)
end
layout(s::Symbol) = s == :row ? LayoutDirection.Row : LayoutDirection.Column
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

@Enum LayoutDirection Column Row
@Enum Alignment Start Center End

@def mutable struct Rect <: DescriptiveUI
  background::Background=Background()
  border::Border=Border()
  radius::Radius=Radius()
  padding::Padding=Padding()
  width::Width=Width()
  height::Height=Height()
  layout_direction::LayoutDirection=LayoutDirection.Column
  child_gap::Length=0px
  align::Alignment=Alignment.Center
end

mixin!(r::Rect, d::LayoutDirection) = r.layout_direction = d

@property Rect.between_width = begin
  self.child_gap + (ismissing(self.border.between_children) ? 0px : self.border.between_children.width)
end

export padding, background, border, rgb, pt, mm, px, Rect, Text, layout, width, height, GrowType, Alignment
