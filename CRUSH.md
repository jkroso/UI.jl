# CRUSH.md

## Project Overview
Julia-based UI library (UI.jl / LUCID.jl) with Conceptual, Descriptive, Specific UI modules.

## Commands
- Activate env: julia --project=.
- Run root tests: julia test.jl
- Run Specific tests: julia --project=Interface/Specific/ test.jl
- Run single test: Edit test file to run specific @testset (using Rutherford.jl)
- Lint/Format: No standard; suggest JuliaFormatter.jl
- Build: None (Julia is interpreted)
- Run example: julia gui/main.jl (check for specifics)

## Code Style
- Imports: @use \"github.com/path\" modules (aliases optional)
- Formatting: 2-space indent, space around operators, no trailing whitespace
- Types: @abstract for abstracts, @mutable for mutables, Union{Nothing,T} for optionals
- Naming: PascalCase types (UINode), snake_case functions/vars, const UPPERCASE
- Error Handling: Standard throw/error; use @test for assertions in tests
- Macros: Use @ui, @dom, @css_str, @match consistently
- Comments: Docstrings for public APIs, inline for complex logic
- Patterns: Functional style, lazy evaluation in components, tree structures for UI
- Files: .jl extensions, Project.toml per module, separate test.jl files