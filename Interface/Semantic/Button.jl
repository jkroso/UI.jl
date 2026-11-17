@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "github.com/jkroso/MiniFB.jl" onkey KeyPress Keys
@use "../Geometric"...
@use "../abstract" SemanticUI WrapMode describe describe! mixin! add_child! theme scale handled inputs sized window_of
@use "../draw" ishovered cursor
@use Colors: @colorant_str, RGB, RGBA

export Button, ButtonGroup

"""
A button. Clicking it calls `onclick(button)` when one is given. The click then
stops at the button. With `primary=true` it's filled with the theme's accent:
use that for the one thing that a page wants you to do next.
"""
@def mutable struct Button <: SemanticUI
  label::String = ""
  onclick::Any = nothing
  primary::Bool = false
end
Button(label::String; kwargs...) = Button(;label=label, kwargs...)
Button(child::SemanticUI; kwargs...) = begin
  b = Button(;kwargs...)
  add_child!(b, child)
  b
end

@def mutable struct ButtonGroup <: SemanticUI end

# A button with a label is as high as a RadioGroup's bar, and its label is the same size, so the
# two sit well side by side. It has a soft shadow under it, which goes while the mouse button is
# down on it. These are the sizes when the theme's text has its usual size.
const BUTTON_H = 30px
const BUTTON_X = 14px   # on each side of the label
const LIFT = RGBA(0.16, 0.1, 0.03, 0.16)   # the colour of the shadow

"True while the mouse button is down on `b`"
pressed(b::Button) = (w = window_of(b); ishovered(b) && w !== nothing && Keys.mouse_left in w.keys)

"The colour `c` with `part` of its light taken away"
darker(c, part) = (c = convert(RGB{Float64}, c); RGB(c.r * (1 - part), c.g * (1 - part), c.b * (1 - part)))

function describe(b::Button)
  t = theme(b)
  k = scale(t)
  down = pressed(b)
  fill = b.primary ? darker(t.accent, down ? 0.2 : ishovered(b) ? 0.09 : 0.0) :
         down ? t.line : ishovered(b) ? t.hover : t.surface
  look = (radius(8px * k), background(fill), (b.primary ? () : (border(1px, :solid, t.line),))...,
          (down ? () : (shadow(0px, 1px * k, 2px * k, LIFT),))..., Alignment.Center)
  # A button that holds a node of its own is as big as that node needs
  b.firstchild isa SemanticUI && return Box(padding(6px * k, 4px * k), look..., describe!(b.firstchild))
  Box(height(BUTTON_H * k), padding(BUTTON_X * k, 0px), look...,
      Text(b.label, size=sized(13pt, t), subfamily="Medium", color=b.primary ? t.on_accent : t.text,
           align=TextAlign.Center, wrap=WrapMode.none))
end

onkey(b::Button, ::KeyPress{Keys.mouse_left}) = b.onclick === nothing ? nothing : (b.onclick(b); handled)
cursor(::Button) = :hand

function describe(b::ButtonGroup)
  Row(border(1px, :solid, theme(b).line),
    (describe!(c) for c in b.children)...)
end

# What `describe` reads, so that it only runs again when one of these changes
inputs(b::Button) = (b.label, b.primary, pressed(b))
