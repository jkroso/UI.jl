# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

LUCID.jl (UI.jl) is a Julia-based UI library implementing a three-phase transformation pipeline. The core insight is that UI programming requires both descending the abstraction ladder (data → pixels) and ascending it (user interactions → conceptual changes).

## Development Commands

### Running Tests
```bash
# Root level tests
julia test.jl

# Specific module tests
julia --project=Interface/Specific/ Interface/Specific/test.jl

# Run with active project environment
julia --project=.
```

### Single Test Execution
Edit the test file to run specific `@testset` blocks. The project uses Rutherford.jl for testing.

## Architecture

### Three-Layer UI Pipeline

The library transforms UI through three distinct phases:

1. **ConceptualUI** (Interface/Conceptual/)
   - Represents UI as users conceptualize it (buttons, menus, forms)
   - Contains all state and event handlers
   - Defined in `Interface/abstract.jl` as the base type
   - Entry point: `gui(data::Any, context::UI)::ConceptualUI`

2. **DescriptiveUI** (Interface/Descriptive/)
   - High-level visual description without state
   - Containers (Box, Row, Column), borders, padding, text styling
   - Enables code reuse across semantically different but visually similar components
   - Entry point: `describe(ui::ConceptualUI)::DescriptiveUI`

3. **ConcreteUI** (Interface/Specific/)
   - Symbolic representation ready for rendering
   - Resolved layout with absolute positions and dimensions
   - Types: ConcreteRect, ConcreteText
   - Entry point: `resolve(ui::DescriptiveUI, context)::ConcreteUI`

### Key Files

- **types.jl**: Core UINode tree structure with Component system
- **Interface/abstract.jl**: Base types for all three UI layers
- **event.jl**: Event system with keyboard/mouse events and bubbling
- **selector.jl**: Data access patterns using identity-based keys
- **style.jl**: CSS-like styling with @style_str macro

### Tree Structure

All UI types extend UITree with sibling/parent relationships:
- `parent`, `prevsibling`, `nextsibling` for traversal
- `firstchild` for lazy child generation in Components
- Custom iterators: SiblingIterator, ChildNodes, ChildSlice

### Component System (types.jl)

Components lazily generate children via `children(c::Component)`. The `@ui` macro provides declarative syntax:

```julia
@ui[Container
  attr=value
  style"property: value"
  child1
  child2]
```

The macro transforms this into `tree(Container(attrs=..., style=...), child1, child2)`.

### Layout Resolution (Interface/Specific/main.jl)

The resolve pipeline:
1. **initialize**: Create ConcreteUI tree with initial dimensions
2. **fit!**: Distribute space among growable/shrinkable children
3. **position!**: Align children within containers based on alignment rules

Key concepts:
- Dimensions have min/max/preferred with GrowType (FitContent, Grow, None)
- Row sizes along x-axis, Column along y-axis
- Text wrapping calculated during fit! phase

### Event System (event.jl)

Events bubble up the tree from target to root. Specialize `on<event>(ui, event)` handlers:
- Mouse events: click, mousedown, mouseup, mousemove, hover
- Keyboard events: keydown, keyup, keypress with modifier keys
- Focus events: focusin, focusout
- Custom events: Submit, Change

The `emit(target, event)` function handles bubbling.

## Code Conventions

### Import Pattern
Use `@use "github.com/user/Package.jl" exports...` for dependencies
```julia
@use "github.com/jkroso/Prospects.jl" @struct @abstract
```

### Type Definitions
- `@abstract struct` for abstract types with default fields
- `@mutable` for mutable struct definitions
- `@def mutable struct` from Prospects.jl

### Styling
- 2-space indentation
- PascalCase for types (UINode, ConcreteRect)
- snake_case for functions and variables

### Property System
Use `@property` macro for computed properties:
```julia
@property UITree.children = SiblingIterator(self.firstchild)
```

## Clay Integration

The `clay/` directory contains a C-based layout engine with Julia bindings in `clay.jl`. Multiple renderers available:
- Terminal (ANSI, termbox2)
- GUI (raylib, cairo)
- Win32 GDI

## Module Structure

Each major component has its own Project.toml:
- Root: Main dependencies (Atom, Colors, MacroTools)
- Interface/: Core UI abstractions
- Interface/Descriptive/: Visual primitives
- Interface/Specific/: Concrete layout engine
- gui/: High-level UI components

## Important Notes

- The library is interpreted (no build step required)
- Components use lazy evaluation to prevent infinite loops in cyclical structures
- The `stale` flag propagates changes up the tree to trigger re-renders
- The `adopt(parent, child)` method allows parents to transform children (e.g., auto-wrapping strings in Buttons)
