@use "github.com/jkroso/Prospects.jl" @def @property @field_str Field ["Enum" @Enum]
@use "github.com/jkroso/Font.jl" Font widths! TTFont ascent descent cap_height ["units" Length px FontUnit absolute relative]
@use "../Geometric"... Width Height
@use "../abstract" describe ConcreteUI
@use GeometryBasics: Vec2, Vec
@use Colors...
@use "github.com/jkroso/MiniFB.jl"... int
@use "github.com/jkroso/MiniFB.jl/skia" SkiaFont font_metrics

@Enum Axis x y

@def mutable struct ConcreteRect <: ConcreteUI
  top::px=0px
  left::px=0px
  height::px=0px
  width::px=0px
  children::Vector{ConcreteUI}=[]
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
  font::Font
  width::px=0px
  height::px=0px
  top::px=0px
  left::px=0px
  lines::Vector{SubString{String}}=Vector[]
  words::Vector{SubString{String}}=Vector[]
  widths::Vector{FontUnit}=Vector[]
end

@property ConcreteText.size = Vec2{px}(self.width, self.height)

"""
1. Instantiate a concrete UI with best guess at the sizing of each element
2. Adjust sizing to distribute available space evenly
3. Wrap Text
4. Adjust heights
6. Align positions of children within rows/columns
"""
function describe(ui::Container, (w, h))
  toplevel = ConcreteRect(width=w, height=h)
  cui = initialize(ui, toplevel)
  push!(toplevel.children, cui)
  fit!(ui, cui)
  position!(ui, cui)
  cui
end

"The initial pass creates the new tree and sets the width of all nodes to their natural value"
function initialize(ui::Row, parent::ConcreteRect)
  rect = invoke(initialize, Tuple{Container, ConcreteRect}, ui, parent)
  if !isgrowable(ui, Axis.x) && ui.width.preferred == 0px
    rect.width = sum(field"width", rect.children, init=0px) + extra_width(rect)
  end
  # Set initial height for children
  for child in rect.children
    h = if child.from.height.preferred != 0px
      child.from.height.preferred
    elseif isgrowable(child, Axis.y)
      internalheight(rect)
    else
      # Use child's natural height
      if child isa ConcreteText
        child.height  # Already set by initialize(::Text)
      else
        maximum(field"height", child.children, init=0px) + extra_height(child)
      end
    end
    child.height = clamp(convert(px, h), minsize(child, field"height"), maxsize(child, field"height"))
  end
  rect
end

function initialize(ui::Box, parent::ConcreteRect)
  rect = invoke(initialize, Tuple{Container, ConcreteRect}, ui, parent)
  if !isgrowable(ui, Axis.x) && ui.width.preferred == 0px
    rect.width = maximum(field"width", rect.children, init=0px) + extra_width(rect)
  end
  if !isgrowable(ui, Axis.y) && ui.height.preferred == 0px
    rect.height = maximum(field"height", rect.children, init=0px) + extra_height(rect)
  end
  rect
end

function initialize(ui::Column, parent::ConcreteRect)
  rect = invoke(initialize, Tuple{Container, ConcreteRect}, ui, parent)
  if !isgrowable(ui, Axis.y) && ui.height.preferred == 0px
    height = sum(field"height", rect.children, init=0px) + extra_height(rect)
    rect.height = height
  end
  rect
end

function initialize(ui::Container, parent::ConcreteRect)
  initial_width = if ui.width.preferred != 0px
    clamp(ui.width.preferred, ui.width.min, ui.width.max)
  else
    clamp(internalwidth(parent), ui.width.min, ui.width.max)
  end
  initial_height = if ui.height.preferred != 0px
    clamp(ui.height.preferred, ui.height.min, ui.height.max)
  else
    clamp(internalheight(parent), ui.height.min, ui.height.max)
  end
  rect = ConcreteRect(from=ui, parent=parent, width=initial_width, height=initial_height)
  rect.children = ConcreteUI[initialize(child, rect) for child in ui.children]
  rect
end

extra_width((;from, children)::ConcreteUI) = begin
  from.padding.width + from.border.width + from.between_width * max(0, length(children) - 1)
end

field(ui, d::Axis) = d == Axis.x ? field"width" : field"height"
isgrowable(ui, d::Axis) = isgrowable(ui, field(ui, d))
isgrowable(ui::ConcreteUI, f::Field) = isgrowable(ui.from, f)
isgrowable(ui::Container, f::Field) = getproperty(ui, f).grow == GrowType.Grow
isgrowable(ui::Union{ConcreteText,Text}, f::Field) = true
isshrinkable(ui, d::Axis) = isshrinkable(ui, field(ui, d))
isshrinkable(ui::ConcreteUI, f::Field) = isshrinkable(ui.from, f)
isshrinkable(ui::Container, f::Field) = getproperty(ui, f).grow != GrowType.None
isshrinkable(ui::Union{ConcreteText,Text}, f::Field) = true

"compute the width inside an element available for it's children to occupy"
function internalwidth((;width, from, children)::ConcreteUI)
  isnothing(from) && return width
  w = width - from.padding.width - from.border.width
  w - from.between_width * max(0, length(children) - 1)
end

internalheight(::Nothing) = 0px
internalheight(ui::ConcreteUI) = ui.height - extra_height(ui)

"Distribute the excess width accross all elements that can accept it"
function grow!(ui::ConcreteRect, direction::Axis)
  prop = field(ui, direction)
  remainder = remaining_size(ui, prop)
  growable = sort!(filter(ui->isgrowable(ui, prop), ui.children), by=prop)
  while !isempty(growable) && remainder > 0px
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
  shrinkable = sort!(filter(ui->isshrinkable(ui, prop), ui.children), by=prop, rev=true)
  while !isempty(shrinkable) && remainder < 0px
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

extra_height((;from, children)::ConcreteRect) = begin
  isnothing(from) && return 0px
  (;padding, border) = from
  h = +(padding.top, padding.bottom, border.bottom.width, border.top.width)
  h + max((length(children)-1) * border.between.width, 0px)
end

sizing_axis(::Row) = Axis.x
sizing_axis(::Column) = Axis.y

function fit!(ui::Box, cui::ConcreteRect)
  for axis in (Axis.x, Axis.y)
    remaining = grow!(cui, axis)
    shrink!(cui, remaining, axis)
  end
  for child in cui.children
    fit!(child.from, child)
  end
end
function fit!(ui::Union{Column,Row}, cui::ConcreteRect)
  remaining = grow!(cui, sizing_axis(ui))
  shrink!(cui, remaining, sizing_axis(ui))
  # fit children along the cross axis
  cross = sizing_axis(ui) == Axis.x ? Axis.y : Axis.x
  cross_field = field(cui, cross)
  available = cross == Axis.y ? internalheight(cui) : internalwidth(cui)
  for child in cui.children
    isgrowable(child, cross) || continue
    setproperty!(child, cross_field, clamp(available, minsize(child, cross_field), maxsize(child, cross_field)))
  end
  for child in cui.children
    fit!(child.from, child)
  end
end

remaining_size(ui::ConcreteRect, f::Field{:height}) = internalheight(ui) - sum(f, ui.children, init=0px)
remaining_size(ui::ConcreteRect, f::Field{:width}) = internalwidth(ui) - sum(f, ui.children, init=0px)

function position!(::Text, ui::ConcreteText) end

# Align contents in both directions
function position!((;padding,border,align, between_width)::Box, ui::ConcreteRect)
  isempty(ui.children) && return
  child = ui.children[1]
  padtop = padding.top
  bordertop = border.top.width
  mintop = ui.top + padtop + bordertop
  h = ui.height - padtop - 2bordertop - padding.bottom
  top = mintop
  if align == Alignment.Center
    space = h - child.height
    top += space/2
  elseif align == Alignment.End
    top += h - child.height
  end
  padleft = padding.left
  borderleft = border.left.width
  minleft = ui.left + padleft + borderleft
  w = ui.width - padleft - 2borderleft - padding.right
  left = minleft
  if align == Alignment.Center
    space = w - child.width
    left += space/2
  elseif align == Alignment.End
    left += w - child.width
  end
  child.top = isapprox(int(mintop), int(top), atol=1) ? mintop : top
  child.left = isapprox(int(minleft), int(left), atol=1) ? minleft : left
  position!(child.from, child)
end

function position!((;padding,border,align, between_width)::Row, ui::ConcreteRect)
  padtop = padding.top
  bordertop = border.top.width
  mintop = ui.top + padtop + bordertop
  h = ui.height - padtop - 2bordertop - padding.bottom
  left = ui.left + padding.left + border.left.width
  for child in ui.children
    top = mintop
    if align == Alignment.Center
      space = h - child.height
      top += space/2
    elseif align == Alignment.End
      top += h - child.height
    end
    child.top = isapprox(int(mintop), int(top), atol=1) ? mintop : top
    child.left = left
    left += child.width + between_width
    position!(child.from, child)
  end
end

function position!((;padding,border,align,between_width)::Column, ui::ConcreteRect)
  padleft = padding.left
  borderleft = border.left.width
  minleft = ui.left + padleft + borderleft
  w = ui.width - padleft - 2borderleft - padding.right
  top = ui.top + padding.top + border.top.width
  for child in ui.children
    left = minleft
    if align == Alignment.Center
      space = w - child.width
      left += space/2
    elseif align == Alignment.End
      left += w - child.width
    end
    child.left = isapprox(int(minleft), int(left), atol=1) ? minleft : left
    child.top = top
    top += child.height + between_width
    position!(child.from, child)
  end
end

minsize(ui::Container, prop::Field) = getproperty(ui, prop).min
minsize(ui::ConcreteUI, prop::Field) = minsize(ui.from, prop)
minsize(ui::ConcreteText, ::Field{:width}) = minimum(word->textwidth(String(word), ui.font), split(ui.from.content), init=0px)

maxsize(ui::Container, prop::Field) = max(getproperty(ui, prop).preferred, getproperty(ui, prop).max)
maxsize(ui::ConcreteText, ::Field{:height}) = ui.height
maxsize(ui::ConcreteText, ::Field{:width}) = px(Inf)
minsize(ui::ConcreteText, ::Field{:height}) = 0px
maxsize(ui::ConcreteUI, prop::Field) = maxsize(ui.from, prop)

# The width of the text element should already of been allocated so here we just wrap the text
# and set the height accordingly
function fit!(from::Text, ui::ConcreteText)
  ui.lines = wraptext(from.content, ui.font.face, ui.width, words=ui.words, widths=ui.widths, size=ui.font.size)
  # Height tracks visible glyph bounds, NOT the font's full line box.
  # A single line is exactly cap_height tall — placing the baseline at the box
  # bottom — so wrapping a Text in a centred Box visually centres the cap area
  # of digits and capitals. Descenders (g, y, p) extend below the box; for
  # multi-line text we add full lineheight per extra line so descenders of one
  # line never collide with caps of the next.
  # We use Skia's actual `capHeight` (varies by font, ~0.72–0.79 × em) instead
  # of Font.jl's 0.72 approximation so the reserved height matches what the
  # renderer will actually draw — otherwise glyphs appear high in their box.
  caph = skia_cap_height(ui.font)
  leading = absolute(from.lineheight, ui.from.size)
  ui.height = caph + convert(px, (length(ui.lines) - 1) * leading)
  nothing
end

function best(growable; by=field"width", comp=(>))
  first = growable[1]
  smallest_val = getproperty(first, by)
  group = Any[first]
  for next in @view(growable[2:end])
    next_val = getproperty(next, by)
    comp(next_val, smallest_val) && return group, next_val
    push!(group, next)
  end
  group, 0px
end

function initialize(ui::Text, parent)
  f = Font(ui.family*':'*ui.subfamily, ui.size)
  words = split(ui.content)
  ConcreteText(from=ui,
               width=textwidth(ui.content, f),
               height=skia_cap_height(f),  # natural height = visible glyph height (single line)
               font=f,
               words=words,
               widths=widths!(words, f.face),
               parent=parent)
end

"Look up Skia's actual cap-height for a Font, in px. Cached by (family, style, size)."
const _skia_cap_height_cache = Dict{Tuple{String,Any,Any},px}()
function skia_cap_height(f::Font)
  key = (f.family, f.style, f.size)
  get!(_skia_cap_height_cache, key) do
    px(font_metrics(SkiaFont(f.family, f.size)).capHeight)
  end
end

function wraptext(s::String, face::TTFont{pem}, max_width::px; words=split(s),
                                                               widths=widths!(words, face),
                                                               size::pt=12pt) where pem
  space_width = textwidth(' ', face)
  limit = relative(FontUnit{pem}, convert(pt, max_width), size)
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

export describe, ConcreteText, ConcreteRect
