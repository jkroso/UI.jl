@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/Font.jl" ["units" px pt]
@use "../Geometric"...
@use "../abstract" SemanticUI describe mixin! describe!
@use "./Icon" Icon
@use Colors: @colorant_str

const key_color = colorant"rgb(60,60,60)"

const mod_icons = Dict(:cmd => "command", :opt => "option", :ctrl => "chevron-up", :shift => "shift")
const key_icons = Dict(:ArrowDown => "arrow-down", :ArrowUp => "arrow-up",
                       :ArrowLeft => "arrow-left", :ArrowRight => "arrow-right",
                       :Delete => "backspace-reverse")

# horizontal padding (5px * 2) + border (1px * 2) = 12px
const keycap_extra = 12px

@def mutable struct KeyCombo <: SemanticUI
  mods::Vector{Symbol} = Symbol[]
  key::Symbol = :a
end

KeyCombo(key::Symbol; mods::Vector{Symbol}=Symbol[]) = KeyCombo(mods=mods, key=key)
KeyCombo(key::Symbol, mods::Symbol...) = KeyCombo(mods=collect(mods), key=key)

keycap(content, w) = begin
  Box(width(w), height(24px), padding(5px, 3px),
      radius(4px), Alignment.Center,
      border(1px, :solid, colorant"rgb(200,200,200)"),
      background(colorant"rgb(250,250,250)"),
      content)
end

describe_icon_key(icon_name::String) = begin
  keycap(describe!(Icon(icon_name, color=key_color, size=14px)), 14px + keycap_extra)
end

describe_text_key(label::String) = begin
  tw = px(length(label) * 9)
  w = max(tw + keycap_extra, 14px + keycap_extra)
  keycap(Box(width(tw), height(grow=GrowType.Grow),
             Text(label, size=11pt, color=key_color)), w)
end

describe(kc::KeyCombo) = begin
  row = Row(height(24px))
  for mod in kc.mods
    icon_name = get(mod_icons, mod, nothing)
    if icon_name !== nothing
      mixin!(row, describe_icon_key(icon_name))
    else
      mixin!(row, describe_text_key(string(mod)))
    end
    mixin!(row, Box(width(3px)))
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
