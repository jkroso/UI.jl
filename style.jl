@use "github.com/jkroso/Font.jl" Font ["units" pt px inch]
@use "github.com/jkroso/Units.jl" Length mm cm m
@use "github.com/jkroso/DOM.jl" styles css Container showstyles @dom ["css" CSSNode class_name]
@use "github.com/jkroso/Sequences.jl/collections/Map.jl" Map assoc
@use "github.com/jkroso/Prospects.jl" @struct @abstract ["Enum.jl" @Enum]
@use "github.com/jkroso/StaticEval.jl" static_eval
@use "github.com/jkroso/Promises.jl" @defer
@use Colors: Color, Colorant, RGB, hex

const transparent = parse(Colorant, "transparent")

struct Style <: AbstractDict{Symbol,Any}
  dict::Map{Symbol,Any}
end

Base.iterate(s::Style) = iterate(s.dict)
Base.iterate(s::Style, state) = iterate(s.dict, state)
Base.length(s::Style) = length(s.dict)
Base.getindex(s::Style, i) = getindex(s.dict, i)
Base.get(s::Style, k, default) = get(s.dict, k, default)

Style(pairs::Pair...) = Style(reduce(add_pair, pairs, init=Map{Symbol,Any}()))

function add_pair(dict, (key, value)::Pair)
  old = get(dict, key, nothing)
  if isnothing(old)
    assoc(dict, key, value)
  else
    assoc(dict, key, merge_style(old, value))
  end
end

const units = Set(Symbol.(split("m mm c pt inch px")))

parse_unit(s::AbstractString) = parse_unit(match(r"([0-9\.]+)(\w+)", s))
parse_unit(m::RegexMatch) = begin
  u = Symbol(m[2])
  @assert u in units
  n = Meta.parse(m[1])
  U = getfield(@__MODULE__(), u)
  U(n)
end

tocss(s::Style) = CSSNode(mapreduce(tocss, merge, values(s.dict), init=Map{Symbol,Any}()))

abstract type StyleNode end
abstract type StyleGroup <: StyleNode end

@struct Padding(top::Union{Missing,Length}=missing,
                right::Union{Missing,Length}=missing,
                bottom::Union{Missing,Length}=missing,
                left::Union{Missing,Length}=missing) <: StyleNode

function tocss(p::Padding)
  allsame(p) && return Map{Symbol,Any}(:padding => tocss(p.top))
  reduce(pairs(p), init=Map{Symbol,Any}()) do d,(k,v)
    ismissing(v) ? d : assoc(d, Symbol(:padding, '-', string(k)), tocss(v))
  end
end

@struct Margin(top::Union{Missing,Length}=missing,
               right::Union{Missing,Length}=missing,
               bottom::Union{Missing,Length}=missing,
               left::Union{Missing,Length}=missing) <: StyleNode

function margin(s, props=())
  vals = collect(eachmatch(r"(\d+)(\w+)", s))
  if !isempty(props)
    v = parse_unit(vals[1])
    return Margin(top=:top in props ? v : missing,
                  right=:right in props ? v : missing,
                  bottom=:bottom in props ? v : missing,
                  left=:left in props ? v : missing)
  end
  length(vals) == 1 && return Margin(fill(parse_unit(vals[1]), 4)...)
  length(vals) == 4 && return Margin(map(parse_unit, vals)...)
  if length(vals) == 2
    v, h = map(parse_unit, vals)
    return Margin(v, h, v, h)
  end
  error("unknown margin value: \"$s\"")
end

function tocss(p::Margin)
  allsame(p) && return Map{Symbol,Any}(:margin => tocss(p.top))
  reduce(pairs(p), init=Map{Symbol,Any}()) do d,(k,v)
    ismissing(v) ? d : assoc(d, Symbol(:margin, '-', string(k)), tocss(v))
  end
end

merge_style(a::T, b::T) where T<:StyleNode = begin
  T((ismissing(getproperty(b, f)) ? getproperty(a, f) : getproperty(b, f) for f in fieldnames(T))...)
end

@Enum BorderStyle none dotted dashed solid double inset grove ridge outset

const black = RGB(0, 0, 0)

@struct BorderSide(width::Length=0mm,
                   style::BorderStyle=BorderStyle.none,
                   color::Colorant=black) <: StyleNode

@struct Border(top::Union{BorderSide,Missing}=missing,
               right::Union{BorderSide,Missing}=missing,
               bottom::Union{BorderSide,Missing}=missing,
               left::Union{BorderSide,Missing}=missing) <: StyleGroup

Border(v::BorderSide) = Border(v, v, v, v)
Border(a::BorderSide, b::BorderSide) = Border(a, b, a, b)

function tocss(b::Border)
  allsame(b) && return Map{Symbol,Any}(:border => tocss(b.top))
  reduce(pairs(b), init=Map{Symbol,Any}()) do d,(k,v)
    ismissing(v) ? d : assoc(d, Symbol(:border, '-', string(k)), tocss(v))
  end
end

tocss(b::BorderSide) = "$(tocss(b.width)) $(b.style) #$(hex(b.color))"
tocss(p::Length) = string(convert(px, p))
allsame(q::StyleGroup) = q.top === q.right && q.right === q.bottom && q.bottom === q.left

@struct Radius(tl::Union{Missing,Length}=missing,
               tr::Union{Missing,Length}=missing,
               br::Union{Missing,Length}=missing,
               bl::Union{Missing,Length}=missing) <: StyleNode

Radius(r) = Radius(r, r, r, r)
Radius(top, bottom) = Radius(top, top, bottom, bottom)

allsame(q::Radius) = q.tl === q.tr && q.tr === q.br && q.br === q.bl

const corner_names = (tl="top-left",tr="top-right",br="bottom-right",bl="bottom-left")

function tocss(b::Radius)
  allsame(b) && return Map{Symbol,Any}(Symbol("border-radius") => tocss(b.tl))
  reduce(pairs(b), init=Map{Symbol,Any}()) do d,(k,v)
    ismissing(v) ? d : assoc(d, Symbol(:border, '-', corner_names[k], "-radius"), tocss(v))
  end
end

function toclass!(s::Style)
  node = tocss(s)
  push!(styles, node)
  css[] = @defer @dom[:style sprint(showstyles)]::Container{:style}
  Symbol(class_name(node))
end

@abstract struct Dimension <: StyleNode
  min::Union{Missing,Length}=missing
  max::Union{Missing,Length}=missing
  value::Union{Missing,Length}=missing
end
@struct Width <: Dimension
@struct Height <: Dimension

Width(value) = Width(missing, missing, value)
Width(min, max) = Width(min, max, missing)
Height(value) = Width(missing, missing, value)
Height(min, max) = Width(min, max, missing)

const arial = Font("Arial")
@struct TextConfig(color::Color=black,
                   font::Font=arial) <: StyleNode

@struct Background(color::Color=transparent) <: StyleNode
@Enum KeyPoint tl tc tr cl center cr bl bc br
@struct RelativePosition(parent::KeyPoint=KeyPoint.tl,
                         self::KeyPoint=KeyPoint.tl) <: StyleNode
@struct Offset(x::Length=0mm, y::Length=0mm) <: StyleNode

const types = (border=Border,
               radius=Radius,
               padding=Padding,
               margin=Margin,
               width=Width,
               height=Height,
               text=TextConfig,
               background=Background,
               relative=RelativePosition,
               offset=Offset)

parse_value(_, _, x::Any) = x
parse_value(::Type{BorderSide}, ::Union{Val{3},Val{:color}}, s::AbstractString) = parse(Colorant, s)
parse_value(::Type{BorderSide}, ::Union{Val{2},Val{:style}}, s::AbstractString) = getproperty(BorderStyle, Symbol(s))
parse_value(::Type{BorderSide}, ::Union{Val{1},Val{:width}}, s::AbstractString) = parse_unit(s)
parse_value(::Type{Radius}, _, s::AbstractString) = parse_unit(s)
parse_value(::Type{Margin}, _, s::AbstractString) = parse_unit(s)
parse_value(::Type{Padding}, _, s::AbstractString) = parse_unit(s)
parse_value(::Type{<:Dimension}, _, s::AbstractString) = parse_unit(s)
parse_value(::Type{TextConfig}, ::Union{Val{1},Val{:color}}, s::AbstractString) = parse(Colorant, s)
parse_value(::Type{TextConfig}, ::Union{Val{2},Val{:font}}, s::AbstractString) = Font(s)
parse_value(::Type{Background}, ::Union{Val{1},Val{:color}}, s::AbstractString) = parse(Colorant, s)
parse_value(::Type{RelativePosition}, _, s::AbstractString) = getproperty(KeyPoint, Symbol(s))
parse_value(::Type{Offset}, _, s::AbstractString) = parse_unit(s)

macro style_str(str)
  static_eval(style_expr(str), __module__)
end

const pair_regex = r"\s*(\w+(?:\[(?:\w|,)+\])?(?:\.\w+)?):\s*([^;\n]+)[;\n$]?"
const selector_regex = r"(\w+)(?:\[([^\]]+)\])?(?:\.(\w+))?"

parse_selector(attr::AbstractString) = begin
  k, p, q = match(selector_regex, attr)
  props = isnothing(p) ? Symbol[] : Symbol.(split(p, ','))
  Symbol(k), props, q
end

leaf_type(D::DataType) = D <: StyleGroup ? leaf_type(fieldtype(D, 1)) : D
leaf_type(u::Union) = leaf_type(u.a <: Missing ? u.b : u.a)

function split_args(str)
  i = 1
  args = Any[]
  current = IOBuffer()
  while i <= length(str)
    c = str[i]
    i = i + 1
    if isspace(c)
      buf = take!(current)
      isempty(buf) || push!(args, String(buf))
    elseif c == '$'
      expr, i = Meta.parseatom(str, i)
      push!(args, expr)
    else
      write(current, c)
    end
  end
  buf = take!(current)
  isempty(buf) ? args : push!(args, String(buf))
end

function style_expr(str)
  pairs = map(eachmatch(pair_regex, str)) do (attr, value)
    key, members, prop = parse_selector(attr)
    T = types[key]
    args = split_args(value)
    if T <: StyleGroup
      LT = leaf_type(T)
      val = if isnothing(prop)
        :($LT($(map(enumerate(args)) do (i,arg)
          parsing_expr(LT, i, arg)
        end...)))
      else
        :($LT(;$(Symbol(prop))=$(parsing_expr(LT, prop, args[1]))))
      end
      val = if isempty(members)
        :($T($val))
      else
        :(let v = $val
          $T(;$((Expr(:kw, m, :v) for m in members)...))
        end)
      end
    else
      isnothing(prop) || push!(members, Symbol(prop))
      val = if isempty(members)
        :($T($(map(enumerate(args)) do (i,arg) parsing_expr(T, i, arg) end...)))
      else
        @assert length(args) == 1
        :(let v = $(parsing_expr(T, members[1], args[1]))
          $T(;$((Expr(:kw, m, :v) for m in members)...))
        end)
      end
    end

    :($(=>)($(QuoteNode(key)), $val))
  end
  :($Style($(pairs...)))
end

"generate an expression that parses the given argument"
parsing_expr(T, key, val) = begin
  if Meta.isexpr(val, :if) # more statically evaluable
    return Expr(:if, val.args[1], parsing_expr(T, key, val.args[2]), parsing_expr(T, key, val.args[3]))
  end
  :($parse_value($T, $(Val(key isa AbstractString ? Symbol(key) : key)), $(esc(val))))
end
