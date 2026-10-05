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

### `focus(ui::SemanticUI)`

Will set the UI element to receive keyboard events

### `emit(ui::SemanticUI, event::Event)`

Triggers the appropriate event handlers. Mouse and keyboard events are automatically emitted so you would only use this event for custom event types such as form submission. The default handler for `emit` will call `onmouse(ui, event)` or `onkey(ui, event)` so if you want to handle mouse and keyboard input then those should be your first choice rather than specialising the emit method. Though either option will work. Though specialising the emit method will prevent event bubbling which is where the even is progressively escalated up the UI tree.

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
- `clip=true`: hide what doesn't fit. Without it, content that can't wrap any further makes its parents wider.

`border(2px, :solid, colour)` draws all four sides. Pick sides with `border(...)[:left, :right]`, and use `border(...; between=true)[:between]` to draw a line between children only.

## Building blocks

- `Image("photo.png", width(grow=GrowType.Grow, max=500px))` draws a PNG or JPEG. If you only fix its width, its height follows the image's aspect ratio.
- `register_font("Fonts/Calistoga-Regular.ttf")` makes a font file usable by its family name, without installing it.
- `Scroll(...)` is a scrolling viewport. You can drag its scrollbar. Arrow keys, Page Up/Down, Home and End scroll it when no element has keyboard focus. Because it keeps its offset on itself, reuse the same instance every frame with `reuse!(scroll, content)`.
- `ishovered(node)` tells a `describe` method whether the cursor is over that node. Define `cursor(::MyNode) = :hand` to change the mouse cursor over it.
- `Link(url) do hovered ... end` opens `url` when clicked. The block returns its geometry, so it can change style on hover.
- `viewport(node)` gives the size the window lays the app out at. Use it to switch layouts by width.
- `frame_stats(window)` gives the time the last frame spent in each stage.
- `toggle_inspector!(window)` opens the layout inspector. It shows the layout tree beside the app, highlights the element under the cursor and lists how that element was sized.
- `Stack(...)` puts its children on top of each other. Later children draw over earlier ones and get clicks first. Use it to float a panel, like a dialog, over a window.
- `scroll_into_view!(scroll, top, bottom)` scrolls the shortest distance that shows that part of a Scroll's content.
- `register_image(key, bytes)` makes PNG or JPEG bytes that are in memory drawable as `Image(key)`.
- `Text(subfamily="Semibold")` picks a weight of an installed font by its name.
- `TextInput(look=(input, text) -> ...)` puts your own geometry around the typed text, in place of the standard box.
- `hide_titlebar!(window)` removes the title bar on macOS, so your app runs to the top edge of the window. Call `drag_window!(window)` from a click on an empty part of your own top bar, so the window can still be moved.
- `dark_mode()` tells you whether macOS is in dark mode. `set_dark!(window, true)` draws the parts of the window that macOS owns, like the close button, to match.
- `TextInput(color=..., placeholder_color=...)` sets the colours of the typed text and of the placeholder.

`examples/25_clay_website.jl` is a port of Clay's website, and it uses most of these. `examples/26_finder.jl` is a file browser modelled on the macOS Finder.
