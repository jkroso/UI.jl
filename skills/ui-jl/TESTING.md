# Testing a window that isn't on the screen

Make a `Window` and never `open` it. Everything works but the screen: layout, drawing, input and popups. The helpers in `Interface/testing.jl` send input through the same handlers as the real mouse and keyboard, and draw a frame after each.

```julia
@use Test: @test, @testset
@use "github.com/jkroso/MiniFB.jl" Window Keys
@use "github.com/jkroso/Font.jl/units" px
@use "github.com/jkroso/UI.jl/Interface/draw" frame rect popups
@use "github.com/jkroso/UI.jl/Interface/testing" click! type! press! move! pixels difference
@use "github.com/jkroso/UI.jl/Interface/save" save_png

w = Window(app, size=(440px, 520px))
frame(w)                           # lay it out and draw it once. Nothing has a rect before this.
click!(w, app.composer.input)      # the middle of a node, or click!(w, (x, y)). click!(w, row, Keys.cmd) holds ⌘.
type!(w, "Buy milk")
press!(w, Keys.enter)              # press!(w, Keys.s, Keys.cmd) for ⌘S
@test length(integrate(app)) == 1
save_png("after.png", w)           # then look at the picture
```

## What to check

- **State**, through the node's fields or `integrate`.
- **Where things are**, with `rect(node)`: `left`, `top`, `width`, `height`, and `children` for the rectangles of its geometry. Each has `from`, the geometry or node it came from.
- **What floats**, with `popups(w)`: each has a `key` and its `content`.
- **The picture.** Save one for each step while you write the test, and read them. Rects can look right while a clip or an offset is wrong. `pixels(path)` and `difference(a, b)` compare two pictures, as `Interface/examples_test.jl` does.

## Things that differ from a real window

- A frame happens only when you call `frame(w)` or a helper does. Code that waits for a second frame, like a popup under a button that was just made, needs another `frame(w)`.
- Work in a Julia task runs only when the test yields. Loop over `frame(w)` and `sleep(0.001)` until it's done, with a time limit.
- A scroll wheel is `onscroll(w, Vec2{px}(dx, dy))` from MiniFB. To reach content further down, set the Scroll's `offset` and draw a frame.
- A native Mac menu doesn't show for a window that isn't on a screen. An app should fall back to a menu that it draws, so that a test can choose from it with the arrow keys and Return.
- Close each window at the end (`close(w)`) when the app keeps a list of its windows.

## Running

- All of UI.jl's tests: `julia --project=. test.jl` in UI.jl's folder. Add words to run only the files whose paths have one: `julia --project=. test.jl Slider`.
- An app's test runs from the app's folder with the app's project. `julia -O0` starts faster, since it only affects code compiled during the run.
- A test must not write the user's real settings, Keychain or files. Give the code under test a folder from `mktempdir()`.
