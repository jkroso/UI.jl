# Color Picker
#
# A full interactive HSV color picker with shade and hue sub-components.
# Demonstrates SubComponent (depends on parent state), drag handling,
# and composite component patterns.

@use "../types.jl" @ui dom
@use "../gui/ColorPicker.jl" ColorPicker
@use Colors: HSV, RGB, hex

# Create a color picker initialized to a blue shade
picker = @ui[ColorPicker(color=HSV(225, 0.8, 0.8))]
println("ColorPicker initialized:")
println("  Color: ", picker.color)
println("  RGB: #", hex(RGB(picker.color)))
println("  Sub-components: ShadePicker + HuePicker")

# Different initial colors
red_picker = @ui[ColorPicker(color=HSV(0, 1.0, 1.0))]
println("\nRed picker: #", hex(RGB(red_picker.color)))

green_picker = @ui[ColorPicker(color=HSV(120, 0.7, 0.9))]
println("Green picker: #", hex(RGB(green_picker.color)))

purple_picker = @ui[ColorPicker(color=HSV(280, 0.6, 0.7))]
println("Purple picker: #", hex(RGB(purple_picker.color)))
