@use "github.com/jkroso/Sequences.jl/collections/Set" Setlet
@use "github.com/jkroso/Prospects.jl" @abstract @struct
@use "github.com/jkroso/Units.jl" Time
@use "./types.jl" UINode

@abstract struct Event
  consumed::Bool=false
end

@enum MouseButton left middle right

@abstract struct MouseEvent <: Event
  target::UINode
end

@struct MouseButtonEvent{type}(button::MouseButton, position::Tuple) <: MouseEvent
@struct MouseHoverEvent{type} <: MouseEvent
@struct ScrollEvent(position::Tuple) <: MouseEvent
@struct MouseMoveEvent(position::Tuple) <: MouseEvent
@struct MouseWheelEvent(delta::Tuple{Int,Int}) <: MouseEvent

struct KeyCombo{key,shft,ctrl,opt,cmd} end
KeyCombo(key;shft=false,ctrl=false,opt=false,cmd=false) = KeyCombo{Symbol(key),shft,ctrl,opt,cmd}()

Base.getproperty(c::KeyCombo{key,shft,ctrl,opt,cmd}, f::Symbol) where {key,shft,ctrl,opt,cmd} = begin
  f == :key && return key
  f == :shft && return shft
  f == :ctrl && return ctrl
  f == :opt && return opt
  f == :cmd && return cmd
  f == :mods && return Setlet((k for (k,v) in zip((:shft,:ctrl,:opt,:cmd),(shft,ctrl,opt,cmd)) if v))
  invoke(getproperty, Tuple{Any,Symbol}, c, f)
end

macro key_str(str)
  key,mods... = split(str, '+')
  KeyCombo{Symbol(key), "shft" in mods,
                        "ctrl" in mods,
                        "opt" in mods,
                        "cmd" in mods}
end

@struct KeyboardEvent{type}(key::KeyCombo) <: Event

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

onkeydown(ui, e::KeyboardEvent) = onkeydown(ui, e.key)
onkeyup(ui, e::KeyboardEvent) = onkeyup(ui, e.key)
onkeypress(ui, e::KeyboardEvent) = onkeypress(ui, e.key)

parse_event(event::AbstractDict, target::UINode) = begin
  parse_event(event_type[event["type"]], event, target)
end

parse_event(T::Type{<:KeyboardEvent}, e::AbstractDict, ::UINode) = begin
  mods = e["modifiers"]
  T(KeyCombo(e["key"], ctrl="ctrl" in mods,
                       opt="alt" in mods,
                       cmd="meta" in mods,
                       shft="shift" in mods))
end

parse_event(::Type{MouseMoveEvent}, e::AbstractDict, target::UINode) = begin
  MouseMoveEvent(tuple(round.(e["position"])...), target)
end

parse_event(::Type{MouseWheelEvent}, e::AbstractDict, target::UINode) = begin
  MouseMoveEvent(tuple(e["delta"]...), target)
end

parse_event(T::Type{<:MouseButtonEvent}, e::AbstractDict, target::UINode) = begin
  T(MouseButton(e["button"]), tuple(round.(e["position"])...), target)
end

parse_event(T::Type{<:MouseHoverEvent}, e::AbstractDict, target::UINode) = T(target)

parse_event(::Type{MouseMoveEvent}, e::AbstractDict, target::UINode) = begin
  MouseMoveEvent(tuple(round.(e["position"])...), target)
end

parse_event(::Type{ScrollEvent}, e::AbstractDict, target::UINode) = begin
  ScrollEvent(tuple(round.(e["position"])...), target)
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
