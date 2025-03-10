@use "github.com/jkroso/Prospects.jl" @abstract @struct ["BitSet.jl" @BitSet setinstances!]
@use "github.com/jkroso/Units.jl" Time
@use "./types.jl" UINode

@abstract struct Event
  consumed::Bool=false
end

@BitSet MouseButton left middle right

@abstract struct MouseEvent <: Event
  target::UINode
end

@struct MouseButtonEvent{type}(button::MouseButton, position::Vector{Int}) <: MouseEvent
@struct MouseHoverEvent{type} <: MouseEvent
@struct ScrollEvent(position::Vector{Int}) <: MouseEvent
@struct MouseMoveEvent(position::Vector{Int}) <: MouseEvent
@struct MouseWheelEvent(delta::Vector{Int}) <: MouseEvent

@BitSet Keys::UInt128
let syntax = "` - = [ ] ; ' , . / * +"
    alphabet = 'a':'z'
    numbers = 0:9
    functionkeys = [Symbol("f$n") for n in 1:19]
    specials = "tab capslock return shft cmd opt ctrl esc delete backspace space fn home pageup pagedown end clear eject left right up down"
  setinstances!(Keys, map(Symbol, vcat(split(syntax), alphabet, numbers, functionkeys, split(specials))))
end

@struct KeyboardEvent{type}(key::Keys) <: Event

@abstract struct Focus <: Event
  target::Union{UINode,Nothing}
end
@struct FocusOut <: Focus
@struct FocusIn <: Focus
const Blur = FocusOut

@struct Submit(value::Any) <: Event
@struct Change(value::Any) <: Event

const event_type = Dict{String,DataType}(
  "keydown" => KeyboardEvent{:down},
  "keyup" => KeyboardEvent{:up},
  "keypress" => KeyboardEvent{:press},
  "mousedown" => MouseButtonEvent{:down},
  "mouseup" => MouseButtonEvent{:up},
  "mousemove" => MouseMoveEvent,
  "mouseover" => MouseHoverEvent{:over},
  "mouseout" => MouseHoverEvent{:out},
  "mousewheel" => MouseWheelEvent,
  "click" => MouseButtonEvent{:click},
  "dblclick" => MouseButtonEvent{:dblclick},
  "scroll" => ScrollEvent,
  "focusin" => FocusIn,
  "focusout" => FocusOut,
  "submit" => Submit,
  "change" => Change)

handler_for(T) = identity

for (e,T) in event_type
  name = Symbol("on", e)
  @eval $name(ui, e) = nothing
  @eval handler_for(::$T) = $name
end

onkeydown(ui, e) = e isa KeyboardEvent && onkeydown(ui, e.key)
onkeyup(ui, e) = e isa KeyboardEvent && onkeyup(ui, e.key)
onkeypress(ui, e) = e isa KeyboardEvent && onkeypress(ui, e.key)

parse_event(event::AbstractDict, target::UINode) = begin
  parse_event(event_type[event["type"]], event, target)
end

parse_event(T::Type{<:KeyboardEvent}, e::AbstractDict, ::UINode) = begin
  mods = e["modifiers"]
  k = lowercase(e["key"])
  k == "meta" && (k="cmd")
  k == "control" && (k="ctrl")
  k == "alt" && (k="opt")
  k == " " && (k="space")
  k == "shift" && (k="shft")
  k == "arrowleft" && (k="left")
  k == "arrowright" && (k="right")
  k == "arrowup" && (k="up")
  k == "arrowdown" && (k="down")
  k == "escape" && (k="esc")
  key = getproperty(Keys, Symbol(k))
  "ctrl" in mods && (key|=Keys.ctrl)
  "alt" in mods && (key|=Keys.opt)
  "meta" in mods && (key|=Keys.cmd)
  "shift" in mods && (key|=Keys.shft)
  T(key)
end

parse_event(::Type{MouseMoveEvent}, e::AbstractDict, target::UINode) = begin
  MouseMoveEvent(round.(e["position"]), target)
end

parse_event(::Type{MouseWheelEvent}, e::AbstractDict, target::UINode) = begin
  MouseMoveEvent(e["delta"], target)
end

parse_event(T::Type{<:MouseButtonEvent}, e::AbstractDict, target::UINode) = begin
  T(MouseButton(UInt8(exp2(e["button"]))), round.(e["position"]), target)
end

parse_event(T::Type{<:MouseHoverEvent}, e::AbstractDict, target::UINode) = T(target)

parse_event(::Type{MouseMoveEvent}, e::AbstractDict, target::UINode) = begin
  MouseMoveEvent(round.(e["position"]), target)
end

parse_event(::Type{ScrollEvent}, e::AbstractDict, target::UINode) = begin
  ScrollEvent(round.(e["position"]), target)
end

"""
Calls the event handler then emits the same event on the targets parent. This recursive event emition is known as
bubbling. You can prevent bubbling by specializing this method
"""
emit(target::UINode, event::Event; handler=handler_for(event)) = begin
  handler == identity || handler(target, event)
  target.parent isa UINode && emit(target.parent, event; handler=handler)
end

@struct Tick(delta::Time, time::Time) <: Event

"""
tick is called on all active UI nodes on each iteration of the render loop
"""
tick(ui::UINode, event) = begin
  for child in ui.children
    tick(child, event)
  end
end
