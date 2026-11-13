@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../abstract" SemanticUI describe mixin! describe! theme scale
@use "../fonts" skia_font
@use "github.com/jkroso/MiniFB.jl/skia" font_metrics text_bounds
@use "./Icon" Icon
@use Colors: @colorant_str

const mod_icons = Dict(:cmd => "command", :opt => "option", :ctrl => "chevron-up", :shift => "shift")
const key_icons = Dict(:ArrowDown => "arrow-down", :ArrowUp => "arrow-up",
                       :ArrowLeft => "arrow-left", :ArrowRight => "arrow-right",
                       :Delete => "backspace-reverse")

# The sizes of a key when the theme has its usual size. `scale()` makes them fit other sizes.
const KEY_HEIGHT = 24px
const ICON_SIZE = 14px
const SIDE_GAP = 5px   # between a key's label and its sides, at least
const BORDER = 1px

@def mutable struct KeyCombo <: SemanticUI
  mods::Vector{Symbol} = Symbol[]
  key::Symbol = :a
end

KeyCombo(key::Symbol; mods::Vector{Symbol}=Symbol[]) = KeyCombo(mods=mods, key=key)
KeyCombo(key::Symbol, mods::Symbol...) = KeyCombo(mods=collect(mods), key=key)

# A box only moves its child to the centre when the move is 2px or more (see
# `place` in Specific), and a key has less room than that. So a key doesn't
# centre its label. Its padding puts the label in the middle.
"A key `w` wide with `content` in it. The content's top left corner is `left` and `top` inside the border."
keycap(content, w, left, top) =
  Box(width(w), height(KEY_HEIGHT * scale()), padding(top, 0px, 0px, left), Alignment.Start,
      radius(4px), border(BORDER, :solid, theme().line), background(theme().surface), content)

describe_icon_key(icon_name::String) = begin
  k = scale()
  w = ICON_SIZE * k + 2SIDE_GAP * k + 2BORDER
  gap = (KEY_HEIGHT * k - 2BORDER - ICON_SIZE * k) / 2
  keycap(describe!(Icon(icon_name, size=ICON_SIZE * k)), w, (w - 2BORDER - ICON_SIZE * k) / 2, gap)
end

# A label is centred by its ink, not by the box its font gives it. A text
# node's box is as tall as a capital letter, with its baseline at the bottom.
describe_text_key(label::String) = begin
  k = scale()
  text = Text(label, size=11pt * k)
  font = skia_font(text.family, text.size, text.subfamily)
  # Skia rounds the ink's edges to whole pixels. It's measured 10 times bigger to get the fractions too.
  ink = text_bounds(skia_font(text.family, 10text.size, text.subfamily), label)
  inkw = px(ink.right - ink.left) / 10
  w = max(inkw + 2SIDE_GAP * k, ICON_SIZE * k + 2SIDE_GAP * k) + 2BORDER
  caps = px(font_metrics(font).capHeight)
  keycap(text, w, (w - 2BORDER - inkw) / 2 - px(ink.left) / 10, (KEY_HEIGHT * k - 2BORDER - caps) / 2)
end

describe(kc::KeyCombo) = begin
  row = Row(height(KEY_HEIGHT * scale()))
  for mod in kc.mods
    icon_name = get(mod_icons, mod, nothing)
    if icon_name !== nothing
      mixin!(row, describe_icon_key(icon_name))
    else
      mixin!(row, describe_text_key(string(mod)))
    end
    mixin!(row, Box(width(3px * scale())))
  end
  isempty(kc.mods) || mixin!(row, Box(width(2px)))
  icon_name = get(key_icons, kc.key, nothing)
  if icon_name !== nothing
    mixin!(row, describe_icon_key(icon_name))
  else
    mixin!(row, describe_text_key(uppercase(string(kc.key))))
  end
  row
end

export KeyCombo
