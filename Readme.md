# UI.jl


```
Data -> SemanticUI -> GeometricUI -> ConcreteUI -> Pixels ───────┐
  │                                                              │
  └──── SemanticUI <- GeometricUI <- ConcreteUI <- User Interaction
```

In prose this is saying the UI pipeline starts with data, from there you define the semantic structure of the UI as the user will think of it: `Button`, `Menu`, `Image`. That kind of thing. You don't concern yourself with how it will actually look at this point. That's for the next step in the pipeline; GeometricUI. This is where you define from a high level how each UI element will look: `Rectangle`, `Line`, `Circle`, `Text` etc... You don't have to specify the size and position of everything though you can if you want. It's whatever level of specificity you prefer. Less specificity is better because it enables the UI to handle different screen sizes. The next step, ConcreteUI is where we pass in the screen size and resolve the geometric description into what is essentially a compressed image. The final step is generating the pixels which can be thought of as image decompression.

The pixels are what the user actually interacts with and these interactions are mapped back up the pipeline to the SemanticUI where through event handlers they affect either the data the UI was derived from or the state of the UI.

To put it another way, you `describe()` you way down the ladder of abstraction from data to pixels, then `interpret()` user input back up to the data. i.e. Going from data to visuals is a chain of describe calls. Responding to user input is a chain of interpret calls.

## API

### `describe(data::Any, [parent::SemanticUI])::SemanticUI`

Create the conceptual structure of the UI. It will be called with the data to be interacted with and the parent UI that the data is to be presented within. Sometimes context matters. For example a string might present differently based in if its the key or the value in a Dictionary. The key might be just a static object while the value might be a text input field.

### `describe(ui::SemanticUI)::GeometricUI`

Takes a semantic description of the UI and gives you a geometric one.

### `describe(ui::GeometricUI, size::Tuple{px,px})::ConcreteUI`

Resolves the geometric description into one of an image appropriate for a given screen size.

### `focus(ui::SemanticUI)`

Will set the UI element to receive keyboard events

### `emit(ui::SemanticUI, event::Event)`

Triggers the appropriate event handlers. Mouse and keyboard events are automatically emitted so you would only use this event for custom event types such as form submission. The default handler for `emit` will call `onmouse(ui, event)` or `onkey(ui, event)` so if you want to handle mouse and keyboard input then those should be your first choice rather than specialising the emit method. Though either option will work. Though specialising the emit method will prevent event bubbling which is where the even is progressively escalated up the UI tree.
