@use Test: @test
@use "../abstract" integrate
@use "./Checkbox" Checkbox
@use "./Toggle" Toggle
@use "./Slider" Slider
@use "./Dropdown" Dropdown
@use "./Select" Select
@use "./RadioGroup" RadioGroup
@use "./ColorPicker" ColorPicker
@use Colors: HSV

# `integrate` reads the value a component holds
@test integrate(Checkbox(checked=true)) === true
@test integrate(Toggle()) === false
@test integrate(Slider(value=3, min=0, max=10)) == 3
@test integrate(Dropdown(options=["Apple", "Banana"], selected=2)) == "Banana"
@test integrate(Dropdown()) === nothing
@test integrate(Select(options=["Apple", "Banana"])) == "Apple"
@test integrate(RadioGroup(labels=["Small", "Large"], selected=2)) == "Large"
@test integrate(ColorPicker(color=HSV(10, 0.5, 0.5))) == HSV(10, 0.5, 0.5)
