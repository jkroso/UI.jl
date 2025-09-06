# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Commands

### Development Environment
- **Activate environment**: `julia --project=.`
- **Run root tests**: `julia test.jl`
- **Run specific interface tests**: `julia --project=Interface/Specific/ test.jl`
- **Run examples**: `julia gui/main.jl`

### Testing
- **Single test execution**: Edit test file to run specific `@testset` (uses Rutherford.jl framework)
- **Test framework**: Uses `@test` and `testset()` from Rutherford.jl
- **Style tests**: Main tests in `test.jl` focus on CSS-style parsing and UI styling

### Code Formatting
- **No standard formatter configured** - suggest using JuliaFormatter.jl if needed
- **Build**: Not applicable (Julia is interpreted)

## Architecture Overview

### High-Level Structure

UI.jl is a comprehensive Julia UI library with a multi-layered architecture implementing conceptual, descriptive, and specific UI representations. The library provides both immediate-mode (Clay-style) and retained-mode UI patterns.

#### Core Architecture Layers

1. **Conceptual Layer** (`Interface/Conceptual/`): User-intent level UI definitions
2. **Descriptive Layer** (`Interface/Descriptive/`): Abstract geometric representation
3. **Specific Layer** (`Interface/Specific/`): Concrete layout with calculated dimensions
4. **GUI Components** (`gui/`): High-level reusable UI components
5. **Clay Integration** (`clay.jl`): Low-level immediate-mode layout engine

### Key Components

#### UI Node System (`types.jl`)
- **`UINode`**: Abstract base for all UI elements with parent/sibling tree structure
- **`Component`**: Lazy-loading UI nodes that generate children on demand  
- **`SubComponent`**: Components that inherit state from parents
- **Tree Management**: Automatic parent/child/sibling relationships with staleness tracking

#### Style System (`style.jl`)
- **CSS-like styling**: `@style_str` macro for CSS-style syntax
- **Style composition**: Border, Padding, Margin, Radius, Background, TextConfig
- **Dynamic parsing**: Runtime parsing of CSS-like strings with Julia expression interpolation
- **Type-safe values**: Length units (px, mm, pt, etc.) with automatic conversion

#### Event System (`event.jl`)
- **Comprehensive events**: Mouse, keyboard, focus, scroll, custom events
- **Event bubbling**: Automatic parent propagation unless consumed
- **Specialized handlers**: Component-specific event handling patterns

#### Layout Engine Integration
- **Clay compatibility**: Integration with Clay immediate-mode layout system
- **Resolution pipeline**: Conceptual → Descriptive → Specific → Rendered
- **Size calculation**: Multi-pass width/height resolution with grow/shrink semantics

### GUI Component Patterns

#### Component Architecture
- **Data binding**: Components automatically bind to data through key-based selection
- **Expandable pattern**: `Expandable` base class for collapsible tree views
- **Editing states**: In-place editing for strings, numbers with cursor management
- **Adoption pattern**: Parent components can wrap/modify children via `adopt()`

#### Key Components
- **Layout**: `HStack`, `VStack` for flexible layouts
- **Data display**: `Table`, expandable data viewers for all Julia types
- **Form controls**: `Button`, `TextInput`, `NumberUI` with validation
- **Interactive**: `Expandable` tree views, `Chevron` controls

### Module Dependencies

The codebase uses a custom `@use` import system from Prospects.jl that provides:
- **Selective imports**: `@use "path" symbol1 symbol2`
- **Nested imports**: `@use "path" ["submodule" symbols...]`
- **GitHub imports**: Direct dependency on `"github.com/user/repo"`

### Testing Philosophy

Tests focus on:
- **Style parsing**: CSS-like syntax validation and conversion
- **Layout resolution**: Width/height calculation in different scenarios  
- **UI tree operations**: Parent/child relationships and state management
- **Component behavior**: Interactive elements and data binding

### Development Patterns

#### UI Creation
```julia
# Macro-based UI construction
@ui[ComponentName attr=value style"css: properties" children...]

# Tree building with automatic parent/child setup
tree(parent, child1, child2, ...)

# Style composition
style"border: 1px solid #fff; padding: 5mm"
```

#### Component Definition
```julia
@mutable ComponentName <: Component
# Define dom() method for HTML output
# Define children() for lazy child generation
# Specialize event handlers as needed
```

#### Layout Resolution
```julia
# Convert conceptual → descriptive → specific
resolve(ui_element, (width_constraint, height_constraint))
```

### Interface Boundaries

- **Conceptual → Descriptive**: `describe()` function strips state, focuses on visual aspects
- **Descriptive → Specific**: `resolve()` calculates concrete dimensions and positions
- **Specific → Rendering**: `dom()` produces HTML/DOM representation
- **Events**: `on()` function handles user interactions and updates state

This architecture enables high code reuse through the separation of concerns between semantic meaning, visual description, concrete layout, and rendering targets.
