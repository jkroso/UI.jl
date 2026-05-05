# Todo List
#
# A classic TodoMVC-style list. Type a task and press Enter to add it.
# Click the checkbox to toggle done; click × to delete. Filter tabs at the
# bottom narrow the visible items to All / Active / Done.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/draw" ui draw
@use "../Interface/abstract" SemanticUI describe describe! focus add_child!
@use "../Interface/Semantic/TextInput" TextInput
@use "../Interface/Semantic/Checkbox" Checkbox
@use Colors: @colorant_str

mutable struct TodoItem
  text::String
  done::Bool
end

@def mutable struct TodoApp <: SemanticUI
  todos::Vector{TodoItem} = TodoItem[]
  input::TextInput = TextInput(placeholder="What needs to be done?")
  filter::Symbol = :all  # :all, :active, :done
end

# --- per-row pieces ---

@def mutable struct TodoRow <: SemanticUI
  item::TodoItem = TodoItem("", false)
  app::Any = nothing  # back-reference so we can remove ourselves
end

@def mutable struct DeleteBtn <: SemanticUI
  row::Any = nothing
end

# --- top-level layout pieces ---

@def mutable struct TodoTitle <: SemanticUI end

@def mutable struct TodoInputRow <: SemanticUI
  input::TextInput = TextInput()
end

@def mutable struct FilterTab <: SemanticUI
  app::Any = nothing
  mode::Symbol = :all
  label::String = "All"
end

@def mutable struct TodoFilters <: SemanticUI
  app::Any = nothing
end

@def mutable struct TodoList <: SemanticUI
  app::Any = nothing
end

@def mutable struct TodoFooter <: SemanticUI
  app::Any = nothing
end

# --- visual descriptions ---

describe(b::DeleteBtn) =
  Box(width(22px), height(22px), Alignment.Center, radius(11px),
      background(colorant"rgb(245,245,245)"),
    Text("x", size=12pt, weight=700, color=colorant"rgb(160,80,80)"))

describe(t::FilterTab) = begin
  active = t.app.filter == t.mode
  Box(padding(6px, 12px), radius(6px),
      background(active ? colorant"rgb(59,130,246)" : colorant"white"),
      border(1px, :solid, active ? colorant"rgb(59,130,246)" : colorant"rgb(220,220,220)"),
    Text(t.label, size=12pt, weight=600,
         color=active ? colorant"white" : colorant"rgb(60,60,60)"))
end

describe(r::TodoRow) = begin
  item = r.item
  done = item.done
  Row(width(grow=GrowType.Grow), height(36px), padding(8px),
      radius(6px), background(colorant"white"),
      border(1px, :solid, colorant"rgb(232,232,232)"),
    describe!(Checkbox(checked=done, onchange=c -> item.done = c.checked)),
    Box(width(10px), height(20px)),
    Box(width(grow=GrowType.Grow), height(20px),
      Text(item.text, size=13pt,
           color=done ? colorant"rgb(160,160,160)" : colorant"rgb(30,30,30)")),
    describe!(DeleteBtn(row=r)))
end

describe(::TodoTitle) =
  Box(width(grow=GrowType.Grow), height(36px),
    Text("Todos", size=22pt, weight=700, color=colorant"rgb(30,30,30)"))

describe(r::TodoInputRow) =
  Row(width(grow=GrowType.Grow), height(40px),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      describe!(r.input)),
    Box(width(8px)))

describe(f::TodoFilters) = begin
  app = f.app
  remaining = count(t -> !t.done, app.todos)
  Row(width(grow=GrowType.Grow), height(28px),
    describe!(FilterTab(app=app, mode=:all,    label="All ($(length(app.todos)))")),
    Box(width(8px)),
    describe!(FilterTab(app=app, mode=:active, label="Active ($remaining)")),
    Box(width(8px)),
    describe!(FilterTab(app=app, mode=:done,   label="Done ($(length(app.todos)-remaining))")))
end

describe(l::TodoList) = begin
  app = l.app
  visible = filter_items(app)
  rows = []
  for (i, it) in enumerate(visible)
    i > 1 && push!(rows, Box(height(6px)))
    push!(rows, describe!(TodoRow(item=it, app=app)))
  end
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), rows...)
end

describe(f::TodoFooter) = begin
  remaining = count(t -> !t.done, f.app.todos)
  Box(width(grow=GrowType.Grow), height(20px),
    Text("$remaining left", size=11pt, color=colorant"rgb(140,140,140)"))
end

describe(app::TodoApp) =
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
         padding(20px), background(colorant"rgb(248,248,250)"),
    describe!(TodoTitle()),
    Box(height(12px)),
    describe!(TodoInputRow(input=app.input)),
    Box(height(16px)),
    describe!(TodoFilters(app=app)),
    Box(height(12px)),
    describe!(TodoList(app=app)),
    describe!(TodoFooter(app=app)))

filter_items(app::TodoApp) =
  app.filter == :all ? app.todos :
  app.filter == :active ? filter(t -> !t.done, app.todos) :
  filter(t -> t.done, app.todos)

# --- behaviour ---

add_from_input!(app::TodoApp) = begin
  text = strip(app.input.text)
  isempty(text) && return
  push!(app.todos, TodoItem(String(text), false))
  app.input.text = ""
  app.input.cursor = 0
  app.input.anchor = 0
end

onkey(b::DeleteBtn, ::KeyPress{Keys.mouse_left}) = begin
  app = b.row.app::TodoApp
  filter!(t -> t !== b.row.item, app.todos)
end
onkey(t::FilterTab, ::KeyPress{Keys.mouse_left}) = (t.app.filter = t.mode)

# Enter in the input adds a todo. The TextInput consumes character keys but
# not Enter, so the event bubbles up to the TodoApp.
onkey(app::TodoApp, ::KeyPress{Keys.enter}) = add_from_input!(app)

const app = TodoApp()
add_child!(app, app.input)  # parent the TextInput so focus() can walk up to the Root
push!(app.todos, TodoItem("Buy milk", false))
push!(app.todos, TodoItem("Read the UI.jl docs", true))
push!(app.todos, TodoItem("Ship 22_todo_list.jl", false))

const window = Window(app, title="Todos", size=(420px, 480px), animating=true)
focus(app.input)

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
