# Calculator
#
# A 4-function calculator. Click digits and operators; ⌫ deletes the last
# entry; C clears everything. Equals (=) finalises the pending operation.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/draw" ui
@use "../Interface/abstract" SemanticUI describe describe!
@use Colors: @colorant_str

@def mutable struct Calc <: SemanticUI
  display::String = "0"
  pending_value::Union{Nothing,Float64} = nothing
  pending_op::Union{Nothing,Symbol} = nothing
  reset_on_next::Bool = false
end

@def mutable struct CalcKey <: SemanticUI
  label::String = ""
  kind::Symbol = :digit  # :digit, :op, :equals, :clear, :backspace, :decimal, :sign
end
CalcKey(label::String, kind::Symbol=:digit) = CalcKey(label=label, kind=kind)

# Click handling: every key knows which Calc it lives in by walking up
function press!(c::Calc, k::CalcKey)
  if k.kind == :digit
    if c.reset_on_next || c.display == "0"
      c.display = k.label
      c.reset_on_next = false
    else
      c.display *= k.label
    end
  elseif k.kind == :decimal
    c.reset_on_next && (c.display = "0"; c.reset_on_next = false)
    occursin('.', c.display) || (c.display *= ".")
  elseif k.kind == :sign
    c.display = startswith(c.display, "-") ? c.display[2:end] : "-" * c.display
  elseif k.kind == :backspace
    c.display = length(c.display) > 1 ? c.display[1:end-1] : "0"
  elseif k.kind == :clear
    c.display = "0"
    c.pending_value = nothing
    c.pending_op = nothing
    c.reset_on_next = false
  elseif k.kind == :op
    apply_pending!(c)
    c.pending_value = parse(Float64, c.display)
    c.pending_op = op_symbol(k.label)
    c.reset_on_next = true
  elseif k.kind == :equals
    apply_pending!(c)
    c.pending_value = nothing
    c.pending_op = nothing
    c.reset_on_next = true
  end
end

op_symbol(label::String) = label == "+" ? :add :
                           label == "-" ? :sub :
                           label == "*" ? :mul :
                           label == "/" ? :div : :noop

apply_pending!(c::Calc) = begin
  isnothing(c.pending_op) && return
  prev = c.pending_value
  cur = parse(Float64, c.display)
  result = c.pending_op == :add ? prev + cur :
           c.pending_op == :sub ? prev - cur :
           c.pending_op == :mul ? prev * cur :
           c.pending_op == :div ? (cur == 0 ? NaN : prev / cur) : cur
  c.display = format_number(result)
end

format_number(x::Float64) = isnan(x) ? "Error" :
                            isinteger(x) && abs(x) < 1e16 ? string(Int(x)) :
                            string(x)

onkey(k::CalcKey, ::KeyPress{Keys.mouse_left}) = press!(k.parent::Calc, k)

# Visual style — Apple-Calculator-ish three-tone palette
key_bg(kind) = kind == :op || kind == :equals ? colorant"rgb(255,159,10)" :
               kind == :clear || kind == :backspace || kind == :sign ? colorant"rgb(165,165,165)" :
               colorant"rgb(80,80,80)"
key_fg(kind) = kind == :clear || kind == :backspace || kind == :sign ? colorant"black" : colorant"white"

describe(k::CalcKey) =
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Alignment.Center, radius(28px), background(key_bg(k.kind)),
    Text(k.label, size=22pt, weight=600, color=key_fg(k.kind), align=TextAlign.Center))

# A spacer that grows in one axis so rows/columns can use it for gaps
spacer(w::px, h::px) = Box(width(w), height(h))

# Wrap each key in a grow cell, with horizontal spacers between
keyrow(keys...) = begin
  cells = []
  for (i, k) in enumerate(keys)
    i > 1 && push!(cells, spacer(8px, 0px))
    push!(cells, Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), describe!(k)))
  end
  Row(width(grow=GrowType.Grow), height(grow=GrowType.Grow), cells...)
end

describe(c::Calc) = begin
  # Pull the keys out of c.children in display-order rows
  ks = collect(c.children)  # 20 CalcKeys, row-major
  row(i) = keyrow(ks[i*4-3], ks[i*4-2], ks[i*4-1], ks[i*4])
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
         padding(12px), background(colorant"black"),
    # Display
    Box(width(grow=GrowType.Grow), height(80px), padding(12px), Alignment.Center,
      Text(c.display, size=40pt, weight=300, family="Helvetica",
           color=colorant"white")),
    spacer(0px, 12px),
    row(1), spacer(0px, 8px),
    row(2), spacer(0px, 8px),
    row(3), spacer(0px, 8px),
    row(4), spacer(0px, 8px),
    row(5))
end

const calc = Calc(
  CalcKey("C", :clear),     CalcKey("<", :backspace),   CalcKey("+/-", :sign),   CalcKey("/", :op),
  CalcKey("7"),              CalcKey("8"),                CalcKey("9"),            CalcKey("*", :op),
  CalcKey("4"),              CalcKey("5"),                CalcKey("6"),            CalcKey("-", :op),
  CalcKey("1"),              CalcKey("2"),                CalcKey("3"),            CalcKey("+", :op),
  CalcKey("0"),              CalcKey(".", :decimal),      CalcKey("00"),           CalcKey("=", :equals))

const window = Window(calc, title="Calculator", size=(280px, 420px), animating=true)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
