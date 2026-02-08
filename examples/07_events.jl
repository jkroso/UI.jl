# Event System
#
# Events bubble up the UI tree from target to root.
# Handle events by specializing on<eventname>(ui, event) for your component type.
#
# Event types:
#   Mouse:    onclick, onmousedown, onmouseup, onmousemove, onmouseover, onmouseout
#   Keyboard: onkeydown, onkeyup, onkeypress (receive Keys bitset)
#   Focus:    onfocusin, onfocusout
#   Data:     Submit(value), Change(value)
#   Time:     Tick(delta, time) - called every render frame

@use "../types.jl" UINode Component @ui tree dom children TextNode
@use "../event.jl" onmousedown onkeydown onclick emit Change Submit Keys MouseButtonEvent
@use "github.com/jkroso/Prospects.jl" @mutable

# --- Click counter ---
@mutable ClickCounter(clicks::Int=0) <: Component
children(ui::ClickCounter) = UINode[TextNode("Clicks: $(ui.clicks)")]

onmousedown(ui::ClickCounter, event) = begin
  ui.clicks += 1
  emit(ui, Change(ui.clicks))
end

counter = @ui[ClickCounter]
println("ClickCounter: ", counter.firstchild.value)

# --- Keyboard handler ---
@mutable KeyLogger(lastkey::String="none") <: Component
children(ui::KeyLogger) = UINode[TextNode("Last key: $(ui.lastkey)")]

onkeydown(ui::KeyLogger, key::Keys) = begin
  ui.lastkey = string(key)
end

logger = @ui[KeyLogger]
println("KeyLogger: ", logger.firstchild.value)

# --- Event bubbling ---
# Events bubble up: child → parent → grandparent → root
# This lets parent components handle events from any descendant

@mutable FormField(label::String="", value::String="") <: Component
@mutable Form(submitted::Bool=false) <: Component

children(ui::FormField) = UINode[TextNode("$(ui.label): $(ui.value)")]
children(ui::Form) = UINode[
  FormField(label="Name", value="Alice"),
  FormField(label="Email", value="alice@example.com")]

# Handle Submit events that bubble up from any child
onclick(ui::Form, event) = begin
  ui.submitted = true
  println("Form submitted!")
end

form = @ui[Form]
println("\nForm structure:")
for child in form.children
  println("  ", child.firstchild.value)
end

# --- Toggle with Change events ---
@mutable Toggle(active::Bool=false) <: Component
children(ui::Toggle) = UINode[TextNode(ui.active ? "ON" : "OFF")]

onmousedown(ui::Toggle, event) = begin
  ui.active = !ui.active
  emit(ui, Change(ui.active))
  ui.stale = true
end

toggle = @ui[Toggle]
println("\nToggle: ", toggle.firstchild.value)
