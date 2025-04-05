@use "github.com/jkroso/Prospects.jl" @def @property @field_str
@use "github.com/jkroso/Font.jl" Font width => textwidth ["units" Length px FontUnit absolute]
@use "../abstract" resolve ConcreteUI
@use "../Descriptive"...

@def mutable struct ConcreteRect <: ConcreteUI
  top::px=0px
  left::px=0px
  height::px=0px
  width::px=0px
  children::Vector{ConcreteUI}
end

@property ConcreteUI.firstchild = self.children[1]
@property ConcreteUI.children = getfield(self, :children)

@def mutable struct ConcreteText <: ConcreteUI
  font::Font
  width::px=0px
  height::px=0px
  lines::Vector{String}=Vector[]
end

"""
1. Fit Sizing Widths
2. Grow and Shrink Sizing Widths
3. Wrap Text
4. Fit Sizing Heights
5. Grow and Shrink Sizing Heights
6. Positions
7. Draw
"""

function resolve(ui::Rect, (w, h))
  cui = initialpass(ui)
  fitwidths!(cui)
  cui
end

"The initial pass creates the new tree and sets the width of all nodes to their natural value"
function initialpass(ui::Rect)
  children = [initialpass(c) for c in ui.children]
  width = ui.width.preferred != 0px ? ui.width.preferred : sum(field"width", children, init=0px)
  ConcreteRect(width=clamp(width, ui.width.min, ui.width.max),
               children=children,
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
  h = ui.from.height.preferred == 0px ? maximum(field"height", ui.children) : ui.from.height.preferred
  ui.height = clamp(h, minheight(ui), maxheight(ui))
end

minwidth(ui::ConcreteUI) = minwidth(ui.from)
minwidth(ui::Rect) = ui.width.min
minwidth(ui::ConcreteText) = minimum(word->textwidth(String(word), ui.font), split(ui.from.content))
minheight(ui::ConcreteText) = ui.height
minheight(ui::ConcreteUI) = minheight(ui.from)
minheight(ui::Rect) = ui.height.min
maxheight(ui::ConcreteText) = ui.height
maxheight(ui::ConcreteUI) = maxheight(ui.from)
maxheight(ui::Rect) = ui.height.max

# The width of the text element should already of been allocated so here we just wrap the text
# and set the height accordingly
function fitwidths!(ui::ConcreteText)
  ui.lines = wraptext(ui.from.content, ui.font, ui.width)
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

function initialpass(ui::Text)
  f = Font(ui.family*':'*ui.subfamily)
  ConcreteText(from=ui, width=textwidth(ui.content, f), font=f)
end

function wraptext(s::String, f::Font, max_width::Length)
  av_width = textwidth(s, f)/length(s)
  default_line_len = max_width ÷ av_width
  start, stop = 1, nextind(s, 1, default_line_len)
  lines = String[]
  while stop < length(s)
    line = s[start:stop]
    i = lastindex(line)
    last_char = line[i]
    w = textwidth(line, f)
    if w > max_width  # shrink the line
      while i > 1
        i = prevind(line, i)
        prev_char = line[i]
        w -= textwidth(prev_char, last_char, f)
        w < max_width && break
        last_char = prev_char
      end
      line = line[1:i]
      stop = nextind(s, start, ncodeunits(line)-1)
    else
      while true # grow the line
        next_char = s[nextind(s, stop)]
        w += textwidth(last_char, next_char, f)
        w > max_width && break
        last_char = next_char
        line = line*next_char
        stop = nextind(s, stop)
      end
    end
    next_char = s[nextind(s, stop)]
    if !isspace(next_char) # backstep to word break
      i = findlast(isspace, line)
      isnothing(i) || (line = s[start:prevind(s,start + i)])
    end
    start += ncodeunits(line)
    stop = start + default_line_len
    line = strip(line)
    isempty(line) || push!(lines, line)
  end
  remainder = strip(s[start:end])
  isempty(remainder) ? lines : push!(lines, remainder)
end

const growexample = Rect(width(600px), background("darkblue"),
                      Rect(width(100px), height(100px), background("red")),
                      Rect(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
                      Rect(width(grow=GrowType.Grow), height(100px), background("yellow")),
                      Rect(width(100px), height(100px), background("lightblue")))

const growmaxed = Rect(width(600px), background("darkblue"),
                    Rect(width(100px), height(100px), background("red")),
                    Rect(width(min=150px, grow=GrowType.Grow), height(100px), background("yellow")),
                    Rect(width(grow=GrowType.Grow, max=150px), height(100px), background("yellow")),
                    Rect(width(100px), height(100px), background("lightblue")))

const shrinkexample = Rect(width(600px), background("darkblue"),
                        Rect(width(min=350px,preferred=350px), height(100px), background("red")),
                        Rect(width(min=50px, grow=GrowType.Grow, preferred=100px), height(100px), background("yellow")),
                        Rect(width(min=100px, grow=GrowType.Grow), height(100px), background("yellow")),
                        Rect(width(100px), height(100px), background("lightblue")))

const textwrap_example = Rect(width(400px), background("darkblue"),
                           Rect(width(min=100px, preferred=150px), height(100px), background("red")),
                           Text("Wibz UIflibber jabberz devz n’ zany toolz setz to flibber flabber snazzy, zippy facez widda wacko eazy twisty"))

# field"width".(resolve(growexample, (600px, 10px)).children)
# field"width".(resolve(growmaxed, (600px, 10px)).children)
# field"width".(resolve(shrinkexample, (600px, 10px)).children)
resolve(textwrap_example, (600px, 10px))
