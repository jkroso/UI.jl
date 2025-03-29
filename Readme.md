# LUCID.jl

UI programming is twice as hard as other types of programming. This is because the ladder of abstraction must be ascended as well as descended. While normally it need only be descended. What I mean by this is UI programming starts with a high level description of what should be shown to the user. This gets translated ultimately into pixels. A data transformation, like all programming tasks. However, the user interacts with these pixels and their interactions need to be mapped back up to the conceptual description of the interface. Hence in a hand wavy kind of way the earlier data transformation needs to be reversible and why I say UI programming is twice as hard.

## API

When working with this library these are the kinds of objects you will be working with:

```
UI
├── ConceptualUI
│   ├── Button
│   ├── Breadcrumb
│   └── …
├── DescriptiveUI
│   ├── Rectangle
│   ├── Text
│   └── …
└── LiteralUI
    ├── Line
    ├── Background
    ├── Shadow
    └── …
```

The order is deliberate. All UI will start with a Semantic UI node. And will likely have at least a few children though not necessarily. The Semantic UI nodes represent the UI as the user would describe it and it's where all state and event handlers are stored.

From the Semantic UI we generate a Descriptive UI tree which represents the UI purely in terms of visual appearance without concern for state or user interactions. However it isn't completely concrete. Some dimensions might be defined as constraints rather than absolute values and a list might be generated within a scroll container without concern for which items will actually be in view.

The final step is generating the Concrete UI from the Descriptive. This is where all constraints are resolved into something that could be considered a symbolic representation of an image. It can very easily be interpreted by a rendering engine and converted into pixels on the screen. In fact if you do a topological sort on the concrete UI you will have a list of draw commands which is something many rendering engines have already been written to interpret.

### gui(data::Any, [context::UI])::ConceptualUI

Create the conceptual structure of the UI. It will be called with the data to be interacted with and the parent UI that the data is to be presented within. Sometimes context matters. For example a string might present differently based in if its the key or the value in a Dictionary. The key might be just a static object while the value might be a text input field.

### visualize(ui::ConceptualUI)::DescriptiveUI

Here is where you convert all your Semantic nodes into Descriptive ones. No state or identity should be retained in the Descriptive UI such that it can be regenerated at any time and replace the old version of itself with no affect. If any step in the pipeline could be skipped it's this one but doing so would dramatically reduce the amount of code reuse you can do since so many Semanticly different UI are very similar at this stage. For example a context menu is almost identical to a normal menu at this stage of the pipeline. Likewise a button and a menu item are visually very similar in the sense that if you were looking at just the draw commands they generate you would struggle to tell them apart.

### resolve(ui::DescriptiveUI, context)::ConcreteUI

This is where you produce a UI tree that represents directly what is to be rendered on screen. Every node should affect at least one pixel. The `context` argument provides information about the available screen space (for layout), and time (for animations)

### emit(event::Event)

Mouse events are mapped back to the conceptual node relevant to them by determining which concrete node was under the cursor then tracing this node back to the conceptual node that generated it.

Keyboard events are simply delivered to the conceptual node that is currently configured to receive them via the `focus(ui)` method
