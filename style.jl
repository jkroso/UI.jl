@use "github.com/jkroso/Units.jl" Length mm cm m ["Typography" pt] ["Imperial" inch]
@use "github.com/jkroso/DOM.jl" styles css Container showstyles @dom ["css" CSSNode class_name]
@use "github.com/jkroso/Sequences.jl/collections/Map.jl" Map assoc
@use "github.com/jkroso/Prospects.jl" @struct
@use "github.com/jkroso/Promises.jl" @defer
@use Colors: Color, Colorant, RGB, hex

struct Style <: AbstractDict{Symbol,Any}
  dict::Map{Symbol,Any}
end

Base.iterate(s::Style) = iterate(s.dict)
Base.iterate(s::Style, state) = iterate(s.dict, state)
Base.length(s::Style) = length(s.dict)
Base.getindex(s::Style, i) = getindex(s.dict, i)
Base.get(s::Style, k, default) = get(s.dict, k, default)

const pair_regex = r"\s*(\w+(?:\[(?:\w|,)+\])?):\s*([^;\n]+)[;\n$]?"
parse_style(style::AbstractString) = Style(reduce(add_pair, eachmatch(pair_regex, style), init=Map{Symbol,Any}()))
add_pair(dict, m) = begin
  k, p = match(r"(\w+)(?:\[([^\]]+)\])?", m[1])
  props = isnothing(p) ? Symbol[] : Symbol.(split(p, ','))
  key = Symbol(k)
  @assert haskey(value_parsers, key) "$key isn't a valid style property name"
  f = getfield(value_parsers, key)
  v = f(m[2], props...)
  old = get(dict, key, nothing)
  if isnothing(old)
    assoc(dict, key, v)
  else
    assoc(dict, key, merge_style(old, v))
  end
end

const units = Set(Symbol.(split("m mm c pt inch")))

parse_unit(s::AbstractString) = parse_unit(match(r"([0-9\.]+)(\w+)", s))
parse_unit(m::RegexMatch) = begin
  u = Symbol(m[2])
  @assert u in units
  n = Meta.parse(m[1])
  U = getfield(@__MODULE__(), u)
  U(n)
end

tocss(s::Style) = CSSNode(mapreduce(tocss, merge, values(s.dict), init=Map{Symbol,Any}()))

abstract type Quadrilateral end

@struct Padding(top::Union{Missing,Length}=missing,
                right::Union{Missing,Length}=missing,
                bottom::Union{Missing,Length}=missing,
                left::Union{Missing,Length}=missing) <: Quadrilateral

padding(s, props...) = begin
  vals = collect(eachmatch(r"(\d+)(\w+)", s))
  if !isempty(props)
    v = parse_unit(vals[1])
    return Padding(top=:top in props ? v : missing,
                   right=:right in props ? v : missing,
                   bottom=:bottom in props ? v : missing,
                   left=:left in props ? v : missing)
  end
  length(vals) == 1 && return Padding(fill(parse_unit(vals[1]), 4)...)
  length(vals) == 4 && return Padding(map(parse_unit, vals)...)
  if length(vals) == 2
    v, h = map(parse_unit, vals)
    return Padding(v, h, v, h)
  end
  error("unknown padding value: \"$s\"")
end

tocss(p::Padding) = begin
  allsame(p) && return Map{Symbol,Any}(:padding => tocss(p.top))
  reduce(pairs(p), init=Map{Symbol,Any}()) do d,(k,v)
    ismissing(v) ? d : assoc(d, Symbol(:padding, '-', string(k)), tocss(v))
  end
end

merge_style(a::T, b::T) where T<:Quadrilateral = begin
  T(ismissing(b.top) ? a.top : b.top,
    ismissing(b.right) ? a.right : b.right,
    ismissing(b.bottom) ? a.bottom : b.bottom,
    ismissing(b.left) ? a.left : b.left)
end

@enum BorderStyle none dotted dashed solid double inset grove ridge outset
const border_styles = string.(instances(BorderStyle))

const black = RGB(0, 0, 0)
@struct BorderAttributes(width::Length=0mm, style::BorderStyle=none, color::Colorant=black)
@struct Border(top::Union{BorderAttributes,Missing}=missing,
               right::Union{BorderAttributes,Missing}=missing,
               bottom::Union{BorderAttributes,Missing}=missing,
               left::Union{BorderAttributes,Missing}=missing) <: Quadrilateral

parse_border_style(s) = BorderStyle(findfirst(==(s), border_styles)-1)
parse_border_attr(m) = begin
  BorderAttributes(width=parse_unit(m[1]),
                   style=isnothing(m[2]) ? solid : parse_border_style(m[2]),
                   color=isnothing(m[3]) ? black : parse(Colorant, m[3]))
end

border(s, props...) = begin
  a = parse_border_attr(match(r"([0-9\.]+\w+)(?:\s(\w+))?(?:\s(.+))?", s))
  isempty(props) && return Border(a, a, a, a)
  Border(top=:top in props ? a : missing,
         right=:right in props ? a : missing,
         bottom=:bottom in props ? a : missing,
         left=:left in props ? a : missing)
end

tocss(b::Border) = begin
  allsame(b) && return Map{Symbol,Any}(:border => tocss(b.top))
  reduce(pairs(b), init=Map{Symbol,Any}()) do d,(k,v)
    ismissing(v) ? d : assoc(d, Symbol(:border, '-', string(k)), tocss(v))
  end
end

tocss(b::BorderAttributes) = "$(tocss(b.width)) $(b.style) #$(hex(b.color))"
tocss(p::Length) = string(convert(pt, p))
allsame(q::Quadrilateral) = q.top === q.right && q.right === q.bottom && q.bottom === q.left

@struct Radius(tl::Union{Missing,Length}=missing,
               tr::Union{Missing,Length}=missing,
               br::Union{Missing,Length}=missing,
               bl::Union{Missing,Length}=missing) <: Quadrilateral

allsame(q::Radius) = q.tl === q.tr && q.tr === q.br && q.br === q.bl

radius(s, corners...) = begin
  v = parse_unit(s)
  isempty(corners) && return Radius(v, v, v, v)
  Radius(:tl in corners ? v : missing,
         :tr in corners ? v : missing,
         :br in corners ? v : missing,
         :bl in corners ? v : missing)
end

const corner_names = (tl="top-left",tr="top-right",br="bottom-right",bl="bottom-left")

tocss(b::Radius) = begin
  allsame(b) && return Map{Symbol,Any}(Symbol("border-radius") => tocss(b.tl))
  reduce(pairs(b), init=Map{Symbol,Any}()) do d,(k,v)
    ismissing(v) ? d : assoc(d, Symbol(:border, '-', corner_names[k], "-radius"), tocss(v))
  end
end

toclass!(s::Style) = begin
  node = tocss(s)
  push!(styles, node)
  css[] = @defer @dom[:style sprint(showstyles)]::Container{:style}
  Symbol(class_name(node))
end

const value_parsers = (padding=padding,
                       border=border,
                       radius=radius)

macro style_str(str)
  parse_style(str)
end
