# Todo UI Generation Design

## Goal

Make `examples/22_todo_list.jl` the north-star example for the downward half of UI.jl's pipeline:

```text
Data -> SemanticUI -> GeometricUI -> ConcreteUI -> Pixels
```

The example should be beautiful enough to sell the library, but its main job is to express the README's staged model clearly.

## Scope

This milestone focuses only on UI generation. It does not try to settle the upward event pipeline or introduce `interpret` as a public API.

## Pipeline Boundary

Semantic nodes are created only while moving from data to `SemanticUI`.

Valid places to create semantic nodes:

- `describe(data)`
- `describe_children(::SemanticUI)` for lazy semantic subtrees

Invalid place to create semantic nodes:

- `describe(::SemanticUI)`, because that method is responsible for lowering an existing semantic tree into `GeometricUI`.

## Todo Example Shape

`describe(::Vector{TodoItem})` should create the top-level semantic tree:

```julia
describe(items::Vector{TodoItem}) =
  TodoApp(todos=items,
    TodoTitle(),
    TodoComposer(TextInput(placeholder="What needs to be done?")),
    TodoFilters(),
    TodoList(),
    TodoFooter())
```

`TodoList` may lazily create row nodes because rows are semantic children:

```julia
describe_children(list::TodoList) =
  map(i -> TodoRow(index=i), visible_indexes(app(list)))
```

Rows should use indexes for now, not direct `TodoItem` references. A row resolves its item from `app.todos[row.index]` when it is lowered.

## Semantic To Geometric Lowering

The example should not call `describe!` directly. Instead, the library should support implicit lowering of semantic children placed inside geometric containers.

The intended mechanism is:

```julia
Base.convert(::Type{GeometricUI}, node::SemanticUI) = begin
  geo = describe(node)
  geo.from = node
  geo
end
```

Geometric containers then deliberately convert semantic children when adopting them. This keeps example code readable while preserving the staged pipeline:

```julia
describe(app::TodoApp) = begin
  title, composer, filters, list, footer = app.children
  Column(..., title, composer, filters, list, footer)
end
```

`describe(app::TodoApp)` consumes existing semantic children; it does not instantiate them.

## Core Library Work

The library needs enough support to make the example run:

- Fix lazy semantic child adoption.
- Add `convert(::Type{GeometricUI}, ::SemanticUI)`.
- Teach geometric parent adoption to lower semantic children.
- Keep `from` links correct so later hit-testing and rendering can trace geometry back to semantic sources.
- Preserve existing explicit geometric children and style mixins.

## Visual Direction

The todo app should feel like a small polished desktop tool:

- Clear title and count summary.
- Compact composer row.
- Filter tabs with visible active state.
- Rows with checkbox, readable task text, and delete affordance.
- Restrained neutral background with enough contrast to inspect layout.

The design should remain simple enough that the code demonstrates the pipeline rather than hiding it behind decoration.
