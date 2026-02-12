@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "github.com/jkroso/MiniFB.jl" MouseMove onmouse
@use "../Geometric"...
@use "../abstract" SemanticUI GeometricUI UITree describe mixin! add_child! describe!
@use "../draw" draw show_tooltip! hide_tooltip!
@use "../Specific"...
@use "./Satellite" AbstractSatellite
@use Colors: @colorant_str

@def mutable struct Tooltip <: AbstractSatellite
  content::Any = nothing
  cached_left::px = 0px
  cached_top::px = 0px
  cached_width::px = 0px
  cached_height::px = 0px
end

Tooltip(content; kwargs...) = Tooltip(;content=content, kwargs...)

Tooltip(label::String, content; kwargs...) = begin
  btn = Box(height(32px), padding(10px), radius(4px),
            Alignment.Center,
            border(1px, :solid, colorant"rgb(200,200,200)"),
            background(colorant"white"),
            Box(height(grow=GrowType.Grow), Alignment.Center, padding(10px),
                Text(label, size=13pt, color=colorant"rgb(30,30,30)")))
  tt = Tooltip(;content=content, kwargs...)
  add_child!(tt, btn)
  tt
end

describe_content(t::Tooltip) = begin
  c = t.content
  if c isa GeometricUI
    Box(padding(8px, 6px), c)
  elseif c isa SemanticUI
    Box(padding(8px, 6px), describe!(c))
  elseif c isa AbstractString
    Box(padding(8px, 6px),
        Box(Text(c, size=12pt, color=colorant"rgb(240,240,240)")))
  else
    Box(padding(8px, 6px),
        Box(Text(string(c), size=12pt, color=colorant"rgb(240,240,240)")))
  end
end

describe(t::Tooltip) = describe(t.firstchild)

onmouse(t::Tooltip, e::MouseMove) = begin
  t.cached_width > 0px && show_tooltip!(e.window, describe_content(t),
                                        t.cached_left, t.cached_top,
                                        t.cached_width, t.cached_height,
                                        placement=t.placement, gap=t.gap)
end

draw(ctx, size, ui::ConcreteRect, t::Tooltip) = begin
  t.cached_left = ui.left
  t.cached_top = ui.top
  t.cached_width = ui.width
  t.cached_height = ui.height
end

export Tooltip
