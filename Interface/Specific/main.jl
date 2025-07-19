@use "github.com/jkroso/Prospects.jl" @def @property @field_str
@use "github.com/jkroso/Font.jl" Font widths! TTFont ["units" Length px FontUnit absolute relative]
@use "../abstract" resolve ConcreteUI
@use "../Descriptive"... Width Height
@use GeometryBasics: Vec2, Vec
@use Colors...
@use "github.com/jkroso/MiniFB.jl"... int

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

"""
1. Fit Sizing Widths
2. Grow and Shrink Sizing Widths
3. Wrap Text
4. Fit Sizing Heights
5. Grow and Shrink Sizing Heights
6. Set Positions
"""
function resolve(ui::Rect, (w, h))
  toplevel = ConcreteRect(width=w, height=h)
  cui = initialize(ui, toplevel)
  push!(toplevel.children, cui)
  if ui.height.grow == GrowType.Grow
    cui.height = h
  end
  resolve!(cui)
  position!(cui)
  cui
end

"The initial pass creates the new tree and sets the width of all nodes to their natural value"
function initialize(ui::Rect, parent)
  rect = ConcreteRect(from=ui, parent=parent, width=parent.width)
  rect.children = ConcreteUI[initialize(c, rect) for c in ui.children]
  rect.width = clamp(if ui.width.preferred != 0px
    ui.width.preferred
  elseif is_width_growable(ui)
    parent.width
  else
    sum(field"width", rect.children, init=0px)
  end, ui.width.min, ui.width.max)
  rect
end

is_width_growable(ui::ConcreteUI) = is_width_growable(ui.from)
is_width_growable(ui::Rect) = ui.width.grow == GrowType.Grow
is_width_growable(ui::Text) = false
is_width_shrinkable(ui::ConcreteText) = true
is_width_shrinkable(ui::Rect) = ui.width.grow != GrowType.None
is_width_shrinkable(ui::Text) = true
is_width_shrinkable(ui::ConcreteUI) = is_width_shrinkable(ui.from)

"compute the width inside an element available for it's children to occupy"
function internalwidth((;width, from, children)::ConcreteUI)
  w = width - from.padding.width - from.border.width
  w - from.between_width * max(0, length(children) - 1)
end

internalheight(::Nothing) = 0px
internalheight(ui::ConcreteUI) = ui.height - extra_height(ui)

"Distribute the excess width accross all elements that can accept it"
function grow!(ui::ConcreteRect, remainder::Length)
  growable = sort!(filter(is_width_growable, ui.children), by=field"width")
  while !isempty(growable) && remainder > 0px # grow
    smallest, next_smallest = best(growable)
    diff = next_smallest == 0px ? remainder/length(smallest) : next_smallest - smallest[1].width
    togrow = min(remainder/length(smallest), diff)
    for child in smallest
      child.width += togrow
      remainder -= togrow
      # When an item has reached it's max size it's no longer growable
      if child.from.width.max <= child.width
        deleteat!(growable, findfirst(==(child), growable))
        x = child.width - child.from.width.max
        child.width = child.from.width.max
        remainder += x # correct for over subtraction
      end
    end
  end
  remainder
end

function shrink!(ui::ConcreteRect, remainder::Length)
  shrinkable = sort!(filter(is_width_shrinkable, ui.children), by=field"width", rev=true)
  while !isempty(shrinkable) && remainder < 0px # shrink
    biggest, next_biggest = best(shrinkable, comp=isless)
    diff = next_biggest == 0px ? remainder/length(biggest) : next_biggest - biggest[1].width
    toshrink = max(remainder/length(biggest), diff)
    for child in biggest
      child.width += toshrink
      remainder -= toshrink
      minw = minwidth(child)
      # When an item has reached it's min size it's no longer shrinkable
      if child.width <= minw
        deleteat!(shrinkable, findfirst(==(child), shrinkable))
        x = child.width - minw
        child.width = convert(px, minw)
        remainder += x # correct for over subtraction
      end
    end
  end
  remainder
end

extra_height(ui::ConcreteRect) = begin
  (;padding, border) = ui.from
  +(padding.top, padding.bottom, border.bottom.width, border.top.width)
end

function resolve!(ui::ConcreteRect)
  shrink!(ui, grow!(ui, internalwidth(ui) - sum(field"width", ui.children, init=0px)))
  foreach(resolve!, ui.children)
  (;height) = ui.from
  if height.grow == GrowType.FitContent
    h = height.preferred == 0px ? maximum(field"height", ui.children, init=0px) + extra_height(ui) : height.preferred
    ui.height = clamp(h, minheight(ui), maxheight(ui))
  elseif height.grow == GrowType.Grow
    ui.height = internalheight(ui.parent)
  end
end

function position!(ui)
  (;padding,border) = ui.from
  padtop = padding.top
  bordertop = border.top.width
  mintop = ui.top + padtop + bordertop
  h = ui.height - padtop - bordertop
  left = ui.left + padding.left + border.left.width
  for child in ui.children
    alignment = ui.from.align
    top = mintop
    if alignment == Alignment.Center
      space = h - child.height
      top += space/2
    elseif alignment == Alignment.End
      top += h - child.height
    end
    child.top = isapprox(int(mintop), int(top), atol=1) ? mintop : top
    child.left = left
    left += child.width + ui.from.between_width
    position!(child)
  end
end

minwidth(ui::ConcreteUI) = minwidth(ui.from)
minwidth(ui::Rect) = ui.width.min
minwidth(ui::ConcreteText) = minimum(word->textwidth(String(word), ui.font), split(ui.from.content), init=0px)
maxwidth(ui::Rect) = min(ui.width.preferred, ui.width.max)
minheight(ui::ConcreteText) = ui.height
minheight(ui::ConcreteUI) = minheight(ui.from)
minheight(ui::Rect) = ui.height.min
maxheight(ui::ConcreteText) = ui.height
maxheight(ui::ConcreteUI) = maxheight(ui.from)
maxheight(ui::Rect) = ui.height.max

# The width of the text element should already of been allocated so here we just wrap the text
# and set the height accordingly
function resolve!(ui::ConcreteText)
  ui.lines = wraptext(ui.from.content, ui.font.face, ui.width, words=ui.words, widths=ui.widths, size=ui.font.size)
  ui.height = convert(px, length(ui.lines) * absolute(ui.from.lineheight, ui.from.size))
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
  f = Font(ui.family*':'*ui.subfamily)
  words = split(ui.content)
  ConcreteText(from=ui,
               width=textwidth(ui.content, f),
               font=f,
               words=words,
               widths=widths!(words, f.face),
               parent=parent)
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
    if w >= limit
      push!(lines, @view s[offset:prevind(s, word.offset)])
      lastword = word
      offset = nextind(s, word.offset)
      w = width
    else
      lastword = word
    end
  end
  offset == lastindex(s) && return lines
  push!(lines, @view s[offset:end])
end

export resolve, ConcreteText, ConcreteRect
