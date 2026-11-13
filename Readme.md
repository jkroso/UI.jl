# UI.jl


```
Data -> SemanticUI -> GeometricUI -> ConcreteUI -> Pixels ───────┐
  │                                                              │
  └──── SemanticUI <- GeometricUI <- ConcreteUI <- User Interaction
```

In prose this is saying the UI pipeline starts with data, from there you define the semantic structure of the UI as the user will think of it: `Button`, `Menu`, `Image`. That kind of thing. You don't concern yourself with how it will actually look at this point. That's for the next step in the pipeline; GeometricUI. This is where you define from a high level how each UI element will look: `Rectangle`, `Line`, `Circle`, `Text` etc... You don't have to specify the size and position of everything though you can if you want. It's whatever level of specificity you prefer. Less specificity is better because it enables the UI to handle different screen sizes. The next step, ConcreteUI is where we pass in the screen size and resolve the geometric description into what is essentially a compressed image. The final step is generating the pixels which can be thought of as image decompression.

The pixels are what the user actually interacts with and these interactions are mapped back up the pipeline to the SemanticUI where event handlers update semantic UI state. When you want the edited domain value, call `integrate(ui)` on the semantic tree. This keeps interaction local to the UI until the program explicitly asks for updated data.

To put it another way, you `describe()` your way down the ladder of abstraction from data to pixels, event handlers mutate the semantic UI tree, and `integrate()` extracts domain data back out of that tree. Going from data to visuals is a chain of describe calls. Going from edited semantic UI back to domain values is an integrate call.

## API

### `describe(data::Any, [parent::SemanticUI])::SemanticUI`

Create the conceptual structure of the UI. It will be called with the data to be interacted with and the parent UI that the data is to be presented within. Sometimes context matters. For example a string might present differently based in if its the key or the value in a Dictionary. The key might be just a static object while the value might be a text input field.

### `describe(ui::SemanticUI)::GeometricUI`

Takes a semantic description of the UI and gives you a geometric one.

### `describe(ui::GeometricUI, size::Tuple{px,px})::ConcreteUI`

Resolves the geometric description into one of an image appropriate for a given screen size.

### `integrate(ui::SemanticUI)`

Extracts the domain data currently represented by a semantic UI tree. This pairs with `describe(data)`: `describe` creates editable semantic state from data, while `integrate` collects that edited state back into domain values.

The components that hold a value define it: `integrate` gives the text of a `TextInput`, whether a `Checkbox` is ticked or a `Toggle` is on, the value of a `Slider`, the chosen option of a `Dropdown`, a `Select` or a `RadioGroup`, and the colour of a `ColorPicker`. Define it for your own nodes in terms of theirs, e.g. `integrate(row::TodoRow) = TodoItem(integrate(row.input), integrate(row.checkbox))`.

### `inputs(ui::SemanticUI)`

Says what `describe(ui)` reads. It's optional. Without it a node is described and laid out on every frame. With it, the node's geometry and its layout are used again until one of the values changes:

```julia
inputs(row::TodoRow) = (row.text, row.done)
```

Give every value that `describe` reads: the node's own fields, the fields of other nodes, and anything outside the tree. Give values, not objects that change in place: `item.done`, not `item`. The library adds the rest itself: whether the mouse is over the node, whether it has the keyboard, the theme, the size of the window and which children the node has. A child that changes is described again by itself, and its new geometry takes the place of its old one in its parent's.

A `describe` that calls `redraw_in!` is run again on the next frame whatever its inputs are. One that reads the time by itself has to give the time as an input.

On a page of 400 rows, a frame that changes one row takes 2.7 ms with `inputs` on the rows, and 10 ms without. Code that's loaded again while the app runs, as `examples/hot_reload.jl` does, describes everything again, so a change to a `describe` always shows. If part of an app looks out of date, an input is missing. `skipping[] = false` turns all of this off, to check. The simple built-in components, like `Button`, `Checkbox`, `Slider` and `Icon`, have their `inputs` already.

### `focus(ui::SemanticUI)`

Will set the UI element to receive keyboard events

### `emit(ui::SemanticUI, event::Event)`

Triggers the appropriate event handlers. Mouse and keyboard events are automatically emitted so you would only use this event for custom event types such as form submission. The default handler for `emit` will call `onmouse(ui, event)`, `onkey(ui, event)` or `ontype(ui, event)` so if you want to handle mouse and keyboard input then those should be your first choice rather than specialising the emit method.

An event bubbles: it goes to the node it's for, then to each semantic node above that one in turn. A handler that returns `handled` stops it there, so a click on a delete button in a row doesn't also select the row:

```julia
onkey(b::DeleteButton, ::KeyPress{Keys.mouse_left}) = (remove!(b.parent); handled)
```

The built-in components keep the clicks they act on. A `TextInput` keeps the keys it uses, and lets the others, like Return, Escape and the up and down arrows, go on up to your own nodes.

A key press says which key went down. `ontype(node, event)` gets each character the user types as `event.char`, after the keyboard's layout, Shift, Option and dead keys have been applied to it. Use it for text, and `onkey` for shortcuts and arrows.

## Layout

Layout follows the same steps as [Clay](https://www.nicbarker.com/clay). Widths are settled first, from the root down. Then text wraps to its final width, images take their height from their aspect ratio and containers measure their content. Last, spare height is shared out and every element is placed. Text is measured with the same Skia font that draws it, so the two always agree.

Each `width(...)` or `height(...)` takes one sizing rule, clamped by `min` and `max`:

- Nothing: fit the content.
- A length, e.g. `width(300px)`: that size. It can still shrink if its siblings don't fit.
- `grow=GrowType.Grow`: start at the content's size, then take an equal share of any spare space.
- `percent=0.5`: that fraction of the parent's space, after padding and gaps.

Containers also take:

- `align`: where children sit across the layout direction.
- `justify`: where the run of children sits along the layout direction.
- `child_gap`: space between children.
- `clip=true`: hide what doesn't fit. Without it, content that can't wrap any further makes its parents wider. `clip_x=true` hides it at the left and right edges only, which keeps the tails of letters in a line of text.

`border(2px, :solid, colour)` draws all four sides. Pick sides with `border(...)[:left, :right]`, and use `border(...; between=true)[:between]` to draw a line between children only. A border can be `:solid`, `:dashed`, `:dotted` or `:double`.

`radius(8px)` rounds every corner. `radius(8px, 0px)` rounds the two at the top only, and `radius(tl, tr, br, bl)` sets each corner.

## Building blocks

- `Image("photo.png", width(grow=GrowType.Grow, max=500px))` draws a PNG or JPEG. If you only fix its width, its height follows the image's aspect ratio.
- `register_font("Fonts/Calistoga-Regular.ttf")` makes a font file usable by its family name, without installing it.
- `Scroll(...)` is a scrolling viewport. You can drag its scrollbar. Arrow keys, Page Up/Down, Home and End scroll it when no element has keyboard focus. A `describe` can make a new one on each frame: the node being described remembers how far it has scrolled. If one `describe` makes several and their order can change, give each a `key`, e.g. `Scroll(key=:files)`. A Scroll that you keep and put back with `reuse!(scroll, content)` still works, and it's the one to use when your `describe` reads `scroll.offset`.
- `rect(node)` tells an event handler where the last layout put a node: a rectangle with `left`, `top`, `width` and `height`, and the rectangles of the node's geometry in `children`. Use it to learn where in the node a click landed, or where to open a menu. `scene(window)` is the rectangle of the whole app.
- `popup!(window, content, anchor=rect(node))` floats `content` over the app, beside the anchor. `content` is an ordinary semantic node or layout, so the components in it work as they do anywhere else, and key presses go to it first. A click outside it, or Escape, closes it. `show_menu!` and `show_tooltip!` are made with it. A menu follows the up and down arrows, and Return picks.
- `ishovered(node)` tells a `describe` method whether the cursor is over that node. Define `cursor(::MyNode) = :hand` to change the mouse cursor over it.
- `Link(url) do hovered ... end` opens `url` when clicked. The block returns its geometry, so it can change style on hover.
- `viewport(node)` gives the size the window lays the app out at. Use it to switch layouts by width.
- `frame_stats(window)` gives the time the last frame spent in each stage.
- `toggle_inspector!(window)` opens the layout inspector. It shows the app's tree beside the app. The Layout tab lists every element the layout made, and the Semantic tab lists only the app's own `SemanticUI` nodes and their fields. Click a row, or click its pick button and then an element in the app, to select an element and list how it was sized.
- `Stack(...)` puts its children on top of each other. Later children draw over earlier ones and get clicks first. Use it to float a panel, like a dialog, over a window.
- `scroll_into_view!(scroll, top, bottom)` scrolls the shortest distance that shows that part of a Scroll's content.
- `register_image(key, bytes)` makes PNG or JPEG bytes that are in memory drawable as `Image(key)`.
- `Text(weight=700)` picks how heavy the letters are: 400 is regular and 700 is bold. `Text(subfamily="Semibold")` picks a weight of an installed font by its name, and wins over `weight`. `Text(subfamily="Italic")` and `"Bold Italic"` pick its slanted letters.
- `TextInput(look=(input, text) -> ...)` puts your own geometry around the typed text, in place of the standard box. A `TextInput` takes what the keyboard types on any layout. It has copy, cut and paste, Home and End, Option with an arrow to move by a word, and a double click to select a word. Text that's longer than the field moves sideways to keep the caret in view.
- `hide_titlebar!(window)` removes the title bar on macOS, so your app runs to the top edge of the window. Call `drag_window!(window)` from a click on an empty part of your own top bar, so the window can still be moved.
- `dark_mode()` tells you whether macOS is in dark mode. `set_dark!(window, true)` draws the parts of the window that macOS owns, like the close button, to match.
- `TextInput(color=..., placeholder_color=...)` sets the colours of the typed text and of the placeholder.
- `with_theme(theme) do ... end` gives the components made inside it their colours and font. Call it in a `describe` method, around the part of the UI the theme is for. `Theme(surface=..., text=..., accent=...)` makes a theme. It also has the colours of the kinds of value the inspector shows: `number`, `string`, `symbol`, `keyword` and `type`. `mono` and `mono_style` are the font that a tree shows its names in, and `size` is the size of those names. `light` and `dark` are ready-made. A `Text` or an `Icon` that isn't given a colour takes the theme's text colour. In a component of your own, read the colours with `theme(node)`, e.g. `background(theme(button).surface)`. It works in `describe`, in `draw` and in event handlers.
- `shadow(0, 4, 12)` gives a container a soft shadow 4px below it. The arguments are how far the shadow moves right and down, then how much it blurs, as in CSS's `box-shadow`. A fourth argument sets its colour, e.g. `shadow(0, 4, 12, "rgba(0,0,0,0.4)")`, and `spread=2px` makes it bigger on every side. The shadow has the container's shape and corner radius, and a `Wedge` casts one in the shape of its slice. A container with `clip=true` and a `Scroll` cut off the shadows of their children at their edges, so give them padding if a child has a shadow.
- `Wedge(inner=0.5, outer=1.0, start=0, sweep=90)` draws a slice of a ring in the middle of its box, like a piece of a pie chart. Its radii are fractions of the biggest circle that fits in the box, and its angles are in degrees, clockwise from 12 o'clock. Only the slice itself gets the cursor, so wedges stacked in one box can each be hovered and clicked.

`examples/25_clay_website.jl` is a port of Clay's website, and it uses most of these. `examples/26_finder.jl` is a file browser modelled on the macOS Finder. `examples/27_disk_usage.jl` shows what's using your disk space as a sunburst chart made of wedges. [Kaydown](https://github.com/jkroso/Kaydown) is a Markdown editor made with UI.jl. It started as an example here and now has its own project.

`julia --project=. examples/hot_reload.jl examples/26_finder.jl` runs an example so that each change you save to it, or to UI.jl, shows in the open window straight away. The window keeps what it was showing. `examples/hot_reload.jl` explains what happens when you change a struct or save a mistake.

## Testing

`julia --project=. test.jl` runs every test. Add words to run only the files whose paths have one of them: `julia --project=. test.jl Slider`.

`Interface/testing.jl` has helpers for testing an app without opening its window. They send input through the same handlers as the real mouse and keyboard:

```julia
w = Window(app, size=(440px, 520px))
frame(w)                              # lay it out and draw it once
click!(w, app.composer.input)         # click the middle of a node, or click!(w, (x, y))
type!(w, "Buy milk")
press!(w, Keys.enter)                 # press!(w, Keys.s, Keys.cmd) holds Cmd
@test length(integrate(app)) == 1
save_png("after.png", w)              # a picture of what the window shows
```

`pixels(path)` reads a picture and `difference(a, b)` says how much of two pictures differs. `Interface/examples_test.jl` uses them to compare the first four examples with the pictures kept beside them.

`julia --project=. examples/finder/build.jl` builds the Finder example into a Mac app that runs without Julia installed, and `examples/disk_usage/build.jl` does the same for Disk Usage. Add `--install` to copy the app into /Applications. `examples/mac_app/build.jl` explains what the build needs.
