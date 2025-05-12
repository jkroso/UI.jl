@use "github.com/jkroso/Prospects.jl" @def @property @field_str
@use "github.com/jkroso/Font.jl" Font widths! TTFont ["units" Length px FontUnit absolute relative]
@use "../abstract" resolve ConcreteUI
@use "../Descriptive"...

@def mutable struct ConcreteRect <: ConcreteUI
  top::px=0px
  left::px=0px
  height::px=0px
  width::px=0px
  children::Vector{ConcreteUI}=[]
end

@property ConcreteUI.firstchild = self.children[1]
@property ConcreteUI.children = getfield(self, :children)

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
6. Positions
"""
function resolve(ui::Rect, (w, h))
  cui = initialize(ui, ConcreteRect(width=w,height=h,from=Rect()))
  if ui.width.grow == GrowType.Grow
    cui.width = w
  end
  if ui.height.grow == GrowType.Grow
    cui.height = h
  end
  fitwidths!(cui)
  cui
end

"The initial pass creates the new tree and sets the width of all nodes to their natural value"
function initialize(ui::Rect, parent)
  children = [initialize(c, ui) for c in ui.children]
  width = ui.width.preferred != 0px ? ui.width.preferred : sum(field"width", children, init=0px)
  ConcreteRect(width=clamp(width, ui.width.min, ui.width.max),
               children=children,
               parent=parent,
               from=ui)
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
internalheight((;height, from, children)::ConcreteUI) = height - from.padding.height - from.border.height

"Distribute the excess width accross all elements that can accept it"
function fitwidths!(ui::ConcreteRect)
  remainder = internalwidth(ui) - sum(field"width", ui.children, init=0px)
  growable = sort!(filter(is_width_growable, ui.children), by=field"width")
  while !isempty(growable) && remainder > 0px # grow
    smallest, next_smallest = top(growable)
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
  shrinkable = sort!(filter(is_width_shrinkable, ui.children), by=field"width", rev=true)
  while !isempty(shrinkable) && remainder < 0px # shrink
    biggest, next_biggest = top(shrinkable, comp=isless)
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
  foreach(fitwidths!, ui.children)
  if ui.from.height.grow == GrowType.FitContent
    h = ui.from.height.preferred == 0px ? maximum(field"height", ui.children, init=0px) : ui.from.height.preferred
    ui.height = clamp(h, minheight(ui), maxheight(ui))
  elseif ui.from.height.grow == GrowType.Grow
    ui.height = internalheight(ui.parent)
  end
  alignchildren!(ui)
end

minwidth(ui::ConcreteUI) = minwidth(ui.from)
minwidth(ui::Rect) = ui.width.min
minwidth(ui::ConcreteText) = minimum(word->textwidth(String(word), ui.font), split(ui.from.content), init=0px)
minheight(ui::ConcreteText) = ui.height
minheight(ui::ConcreteUI) = minheight(ui.from)
minheight(ui::Rect) = ui.height.min
maxheight(ui::ConcreteText) = ui.height
maxheight(ui::ConcreteUI) = maxheight(ui.from)
maxheight(ui::Rect) = ui.height.max

# The width of the text element should already of been allocated so here we just wrap the text
# and set the height accordingly
function fitwidths!(ui::ConcreteText)
  ui.lines = wraptext(ui.from.content, ui.font.face, ui.width, words=ui.words, widths=ui.widths, size=ui.font.size)
  ui.height = convert(px, length(ui.lines) * absolute(ui.from.lineheight, ui.from.size))
  nothing
end

function top(growable; by=field"width", comp=(>))
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

function alignchildren!(ui::ConcreteRect)
  padtop = ismissing(ui.from.padding.top) ? 0px : ui.from.padding.top
  bordertop = ismissing(ui.from.border.top) ? 0px : ui.from.border.top
  mintop = padtop + bordertop
  h = ui.height - mintop
  for child in ui.children
    alignment = ui.from.align
    top = mintop
    if alignment == Alignment.Center
      top += (h - child.height)/2
    elseif alignment == Alignment.End
      top += h - child.height
    end
    child.top = top
  end
end

export resolve, ConcreteText, ConcreteRect
