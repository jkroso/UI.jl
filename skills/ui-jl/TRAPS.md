# Traps

Each of these cost time in a real session. Check the ones that your layout touches.

## Layout

- **`padding(x, y)` is sides first.** `padding(10px, 4px)` is 10px left and right, 4px top and bottom. `padding(t, r, b, l)` with four goes clockwise from the top. `padding(n)` is every side.
- **Children are centred unless you say so.** A container's `align` is `Alignment.Center`. Pass `Alignment.Start` for text that starts at the left, and `justify=Alignment.End` to push the run of children to the far end.
- **A bare `Text` in a `Row` grows.** Beside a `Box(width(grow=GrowType.Grow))` it takes half the spare width, and its words start in the middle of the row. Wrap it: `Box(Text(...))`. A Box with no width is as wide as what it holds.
- **Text that can't wrap makes its parents wider.** Give the container `clip=true`, or `clip_x=true` to keep the tails of the letters, when long text must stop at an edge.
- **`offset_x` and `offset_y` move the container that has them**, with all that's in it, and its clip edges too. To scroll content under a fixed clip, clip an outer container and offset an inner one: `Row(clip_x=true, Box(offset_x=-x, child))`.
- **A long list needs only the rows in view.** Thousands of nodes make each frame slow. Work out which rows the scroll shows from `scroll.offset` and the row height, build those, and put an empty `Box(height(...))` above and below for the rest. A `describe` that reads `scroll.offset` needs a Scroll that's kept and put back with `reuse!(scroll, content)`.
- **`rect(node)` is from the last frame.** It's `nothing`, or stale, for a node that wasn't drawn in it. Draw a frame before you read it, and don't anchor a popup to a button that was made this frame.

## Events and state

- **A menu item that throws is caught and logged.** An item that "does nothing" most likely threw. Call its action yourself in a test to see the error.
- **A new object each frame loses its state.** A `TextInput` or a `Scroll` made inside `describe` is matched to last frame's by the place it was made at. If the order of what a `describe` makes can change, keep the node yourself, or give a `Scroll` a `key`.
- **⌘ shortcuts from scripts.** A scripted key press may reach a real window as a plain letter. To test a shortcut, set the held keys on the window and call the handler, as `press!(w, Keys.s, Keys.cmd)` does.

## Loading and running

- **Kip caches a file by its own text.** A file that `include`s another doesn't recompile when only the other changes. Split code with `@use "./file"`, not `include`.
- **Two copies of one file.** If an app loads `UI.jl/Interface/abstract` by one path and a test loads it by another, there are two modules, and `window_of(node)` or a `describe` method "has no method". Load UI.jl's files by the same path everywhere, or take the names from the app's own module.
- **A failed compile can leave a marker** (`.noprecompile` in `~/.kip/cache/<hash>/`) that makes later loads slow with no message. It has happened after a change to Kip's source, after a test run from UI.jl's own folder, and after a script outside the app's folder loaded UI.jl. The run prints "Module Kip with build ID ... is missing from the cache". `find ~/.kip/cache -name .noprecompile -mmin -30` lists new ones.
- **A window needs a display.** A window test crashes in `glfwGetVideoMode` (signal 11) while the lid is closed or the display sleeps. Check that before you blame a change.
- **A video or a sound never loads under `sleep`.** The Mac's media code needs the run loop to turn. See `Interface/Semantic/Player_test.jl` for how its tests wait.
- **A hot-reload window can end up with two copies of UI.jl** after UI.jl itself changes a lot. If the window says that it couldn't draw, restart the hot-reload run.
