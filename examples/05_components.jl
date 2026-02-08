# Components
#
# The @ui macro provides declarative syntax for building component trees.
# Components lazily generate children and support event handling.
#
# Syntax: @ui[ComponentType(kwargs...) style"..." children...]

@use "../types.jl" UINode Component @ui tree dom children TextNode
@use "../event.jl" onmousedown emit Change
@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl" @dom @css_str

# --- Button ---
@use "../gui/Button.jl" Button ButtonGroup

# A simple button
button = @ui[Button "Click me"]
println("Button: ", typeof(button))
println("  Text: ", button.firstchild.value)

# A button group - strings are automatically wrapped in Buttons via adopt()
group = @ui[ButtonGroup "Years" "Months" "Days" "Hours"]
println("\nButtonGroup children:")
for child in group.children
  println("  ", typeof(child), " → \"", child.firstchild.value, "\"")
end

# --- Switch ---
@use "../gui/Switch.jl" Switch

toggle = @ui[Switch]
println("\nSwitch value: ", toggle.value)

toggle_on = @ui[Switch(value=true)]
println("Switch (on) value: ", toggle_on.value)

# --- TextInput ---
@use "../gui/TextInput.jl" TextInput

input = @ui[TextInput(value="Hello", placeholder="Type here")]
println("\nTextInput value: \"", input.value, "\"")
println("TextInput placeholder: \"", input.placeholder, "\"")

# Styled TextInput using the style string macro
@use "../style" @style_str
styled_input = @ui[TextInput(value="styled", placeholder="Search...")
                   style"padding: 3mm; margin[top,bottom]: 3mm"]
println("Styled TextInput style: ", styled_input.style)

# --- Custom Component ---
# Define your own component by extending Component

@mutable Counter(count::Int=0) <: Component

children(ui::Counter) = UINode[TextNode("Count: $(ui.count)")]

onmousedown(ui::Counter, event) = begin
  ui.count += 1
  ui.stale = true
end

counter = @ui[Counter(count=42)]
println("\nCustom Counter: ", counter.firstchild.value)
