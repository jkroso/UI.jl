# UI.jl

Retained mode vs Immediate mode is normally seen as a dichotomy in UI programming but all UI are a mix of both because even a "pure" immediate mode UI will have some global state passed in from the top making it retained mode at the highest level. While a "pure" retained mode UI would only be truely pure if it maintained it's own pixel buffer and performed no logic at draw time which makes it immediate mode at the lowest level. So the dichotomy is really just at what point should you switch from retained mode to immediate mode. The answer to this question is obviously going to be it depends. So your UI library should allow you to choose when you switch. The definition of retained mode and immediate mode has been blurred by the reluctance of programmers to switch between paradigms and instead find clever workarounds that ultimately amount to switching modes without admitting it. What's going on is something very similar to the debate over object orientated programming vs functional programming. Which object orientated being analogous to retained mode and functional being analogous to immediate mode. But really it's just a debate over API preference. All programs are object orientated if you go down to the hardware level because the computer is an object.

Julia removed the compromises that drive the debate over function vs object orientated. And this library does the same with the debate over retained vs immediate mode. I'm going to replace the terms retained mode, and immediate mode from here on out because I think they obfuscate the purpose of each. Retained mode will be call Conceptual UI, and Immediate mode will be call Declarative UI. I'll also introduce a third term which is Concrete UI. The three types form a pipeline that can't profitably be abbreviated in anything other than trivial applications.

## API

When working with this library these are the kinds of objects you will be working with:

```
UI
├── ConceptualUI
│   ├── Button
│   ├── Breadcrumb
│   └── ...
├── DeclarativeUI
│   ├── Rectangle
│   ├── Text
│   └── ...
└── ConcreteUI
    ├── Line
    ├── Background
    ├── Shadow
    └── ...
```

The order is deliberate. All UI will start with a Conceptual UI node. And will likely have at least a few children though not necessarily. The Conceptual UI nodes represent the UI as the user would describe it and it's where all state and event handlers are stored.

From the Conceptual UI we generate a Declarative UI tree which represents the UI purely in terms of visual appearance without concern for state or user interactions. However it isn't completely concrete. Some dimensions might be defined as constraints rather than absolute values and a list might be generated within a scroll container without concern for which items will actually be in view.

The final step is generating the Concrete UI from the Declarative. This is where all constraints are resolved into something that could be considered a symbolic representation of an image. It can very easily be interpreted by a rendering engine and converted into pixels on the screen. In fact if you do a topological sort on the concrete UI you will have a list of draw commands which is something many rendering engines have already been written to interpret.

### gui(data::Any, [context::UI])::ConceptualUI

Create the conceptual structure of the UI. It will be called with the data to be interacted with and the parent UI that the data is to be presented within. Sometimes context matters. For example a string might present differently based in if its the key or the value in a Dictionary. The key might be just a static object while the value might be a text input field.

### visualize(ui::ConceptualUI)::DeclarativeUI

Here is where you convert all your Conceptual nodes into Declarative ones. No state or identity should be retained in the Declarative UI such that it can be regenerated at any time and replace the old version of itself with no affect.

### resolve(ui::DeclarativeUI, context)::ConcreteUI

This is where you produce a UI tree that represents directly what is to be rendered on screen. Every node should affect at least one pixel. The `context` argument provides information about the available screen space.
