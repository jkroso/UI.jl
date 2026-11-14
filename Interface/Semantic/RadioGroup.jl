@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl/skia" rounded_rectangle
@use "github.com/jkroso/MiniFB.jl" Keys KeyPress onkey int
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../Geometric"...
@use "../Specific"... text_width
@use "../abstract" SemanticUI WrapMode describe describe! theme scale handled integrate inputs sized carry! step_animation ease
@use "../draw" draw cursor ishovered redraw_in!
@use Colors: @colorant_str, RGBA

@def mutable struct RadioGroup <: SemanticUI
  selected::Int = 1
  labels::Vector{String} = String[]
  # Called after a click picks a choice. `group.selected` is the new choice.
  onchange::Function = group -> nothing
  # The choice that was picked before the last click, so that the raised choice can slide
  # from there, how far it has slid, from 0 to 1, and when it last moved
  was::Int = 0
  slid::Float64 = 1.0
  stepped::Float64 = 0.0
end

@def mutable struct RadioItem <: SemanticUI
  group::RadioGroup
  index::Int
  wide::Any = nothing   # how wide its part of the bar is
end

cursor(::RadioItem) = :hand

onkey(item::RadioItem, ::KeyPress{Keys.mouse_left}) = begin
  g = item.group
  g.selected == item.index && return handled
  g.was, g.slid, g.stepped = g.selected, 0.0, time()
  g.selected = item.index
  g.onchange(g)
  handled
end

# A RadioGroup is a bar of choices side by side, like a Mac's segmented control. The one
# that's picked is raised: it has the background that components put text on, and a soft
# shadow. When a click picks another choice, the raised part slides across to it.
# These are the sizes when the theme's text has its usual size.
const CHOICE_H = 26px   # of each choice
const BAR_PAD = 2px     # between the bar's edge and the choices, and between two choices
const CHOICE_X = 14px   # inside a choice, on each side of its label
const LIFT = RGBA(0.16, 0.1, 0.03, 0.3)   # the colour of the shadow under the picked choice
const SLIDE = 0.24      # seconds the raised part takes to slide to a new choice

describe(item::RadioItem) = begin
  t = theme(item)
  k = scale(t)
  picked = item.index == item.group.selected
  Box(width(preferred=item.wide, grow=GrowType.None), height(CHOICE_H * k), Alignment.Center, radius(6px * k),
      (picked || !ishovered(item) ? () : (background(t.hover),))...,
    # The label is in a box of its own, so it stays in the middle and doesn't grow into the spare room
    Box(Text(item.group.labels[item.index], size=sized(13pt, t), subfamily=picked ? "Medium" : "",
             color=picked ? t.text : t.dim, wrap=WrapMode.none)))
end

describe(rg::RadioGroup) = begin
  t = theme(rg)
  k = scale(t)
  n = length(rg.labels)
  # Each choice is as wide as its label is when it's picked, so no choice moves when the pick does
  widths = [text_width(Text(l, size=sized(13pt, t), subfamily="Medium"), l) + 2CHOICE_X * k for l in rg.labels]
  lefts = [sum(widths[1:i-1], init=0px) + (i - 1) * BAR_PAD * k for i in 1:n]
  items = [describe!(RadioItem(group=rg, index=i, wide=widths[i])) for i in 1:n]
  bar = Row(height(CHOICE_H * k), child_gap=BAR_PAD * k, items...)
  frame = (height((CHOICE_H + 2BAR_PAD) * k), Alignment.Start, padding(BAR_PAD * k), radius(8px * k), background(t.line))
  n == 0 && return Stack(frame..., bar)
  to = clamp(rg.selected, 1, n)
  from = rg.was in 1:n ? rg.was : to
  # Where the raised part is on its way from the last choice to this one. Each frame moves it on.
  if rg.slid < 1
    rg.slid, rg.stepped = step_animation(rg.slid, rg.stepped, SLIDE)
    redraw_in!(rg, 1/60)
  end
  d = ease(rg.slid)
  x = lefts[from] + (lefts[to] - lefts[from]) * d
  w = widths[from] + (widths[to] - widths[from]) * d
  Stack(frame...,
    Box(width(preferred=w, grow=GrowType.None), height(CHOICE_H * k), offset_x=x, radius(6px * k),
        background(t.surface), shadow(0px, 1px * k, 3px * k, LIFT)),
    bar)
end

"The label of the choice that's picked, or `nothing` when there are no choices"
integrate(rg::RadioGroup) = isempty(rg.labels) ? nothing : rg.labels[clamp(rg.selected, 1, length(rg.labels))]

# What `describe` reads, so that it only runs again when one of these changes
inputs(rg::RadioGroup) = (rg.labels, rg.selected, rg.slid)

# A group made again in place of this one, as when the code that made it runs again, slides on from where it was
carry!(new::RadioGroup, old::RadioGroup) = begin
  new.was, new.slid, new.stepped = old.was, old.slid, old.stepped
  new
end
inputs(item::RadioItem) = (item.index, item.group.selected, item.group.labels, item.wide)

export RadioGroup
