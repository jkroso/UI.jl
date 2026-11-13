@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "github.com/jkroso/MiniFB.jl" MouseMove onmouse
@use "../Geometric"...
@use "../abstract" SemanticUI GeometricUI UITree describe mixin! add_child! describe! theme scale sized
@use "../draw" show_tooltip! hide_tooltip! rect
@use "../Specific"...
@use "./Satellite" AbstractSatellite
@use Colors: @colorant_str

@def mutable struct Tooltip <: AbstractSatellite
  label::String = ""
  content::Any = nothing
end

Tooltip(content; kwargs...) = Tooltip(;content=content, kwargs...)
Tooltip(label::String, content; kwargs...) = Tooltip(;label=label, content=content, kwargs...)

describe_content(t::Tooltip) = begin
  content = t.content
  if content isa SemanticUI
    Box(padding(8px, 6px), describe!(content))
  elseif content isa GeometricUI
    Box(padding(8px, 6px), content)
  elseif content isa AbstractString
    Box(padding(8px, 6px),
        Box(Text(content, size=sized(12pt, theme(t)), color=colorant"rgb(240,240,240)")))
  else
    Box(padding(8px, 6px),
        Box(Text(string(content), size=sized(12pt, theme(t)), color=colorant"rgb(240,240,240)")))
  end
end

describe(t::Tooltip) = begin
  isempty(t.label) && return describe(t.firstchild)
  k = scale(theme(t))
  Box(padding(18px * k, 15px * k, 15px * k, 15px * k), radius(4px),
      Alignment.Center,
      border(1px, :solid, theme(t).line),
      background(theme(t).surface),
      Text(t.label, size=sized(13pt, theme(t))))
end

onmouse(t::Tooltip, e::MouseMove) = begin
  r = rect(t)
  r === nothing || show_tooltip!(e.window, describe_content(t), r.left, r.top, r.width, r.height,
                                 placement=t.placement, gap=t.gap)
end

export Tooltip
