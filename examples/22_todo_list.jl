# Todo List
#
# Demonstrates the library's progressive-describe pipeline:
#
#     Data            → SemanticUI       → GeometricUI    → ConcreteUI
#     Vector{TodoItem}  TodoApp/TodoRow/…  Column/Row/Box…  positioned rects
#
# Each level only knows how to translate to the next. Drawing primitives
# fall out at the end. Keeping the bridges as `describe` methods means the
# raw data type is the entry point — no hand-assembling a tree at the call
# site, just `describe(todos)`.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/draw" ui draw
@use "../Interface/abstract" SemanticUI describe describe_children describe! focus add_child!
@use "../Interface/Semantic/TextInput" TextInput
@use "../Interface/Semantic/Checkbox" Checkbox
@use Colors: @colorant_str

# --- data layer ---

mutable struct TodoItem
  text::String
  done::Bool
end

const data = [
  TodoItem("Buy milk", false),
  TodoItem("Read the UI.jl docs", true),
  TodoItem("Ship 22_todo_list.jl", false)]

# --- semantic layer (domain UI types) ---
@def mutable struct DeleteBtn <: SemanticUI
  row::Any = nothing
end

@def mutable struct TodoTitle <: SemanticUI end

@def mutable struct TodoInputRow <: SemanticUI
  input::TextInput = TextInput()
end

@def mutable struct FilterTab <: SemanticUI
  mode::Symbol = :all
  label::String = "All"
end
@def mutable struct TodoFilters <: SemanticUI end
@def mutable struct TodoList <: SemanticUI end
@def mutable struct TodoRow <: SemanticUI
  index::Int8
end
@def mutable struct TodoFooter <: SemanticUI end

describe_children(ui::TodoList) = begin
  map(i->TodoRow(index=i), 1:length(ui.parent.todos))
end

# --- describe: data → SemanticUI ---
describe(items::Vector{TodoItem}) = begin
  TodoApp(todos=items,
    TextInput(placeholder="What needs to be done?"),
    TodoFilters(),
    TodoList(),
    TodoFooter())
end

# --- describe: SemanticUI → GeometricUI ---
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
  visible = visible_items(app)
  rows = []
  for (i, it) in enumerate(visible)
    i > 1 && push!(rows, Box(height(6px)))
    push!(rows, describe!(TodoRow(item=it, app=app)))
  end
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), rows...)
end

describe(f::TodoFooter) = begin
  remaining = count(t -> !t.done, f.parent.todos)
  Box(width(grow=GrowType.Grow), height(20px),
    Text("$remaining left", size=11pt, color=colorant"rgb(140,140,140)"))
end

describe(app::TodoApp) = begin
  (title, input, filters, list, footer) = app.children
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
         padding(20px), background(colorant"rgb(248,248,250)"),
    describe!(title),
    Box(height(12px)),
    describe!(input),
    Box(height(16px)),
    describe!(filters),
    Box(height(12px)),
    describe!(list),
    describe!(footer))
end

# --- helpers / behaviour ---

visible_items(app::TodoApp) =
  app.filter == :all ? app.todos :
  app.filter == :active ? filter(t -> !t.done, app.todos) :
  filter(t -> t.done, app.todos)

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

# --- entry: data → SemanticUI → Window ---

const todoui = describe(data)
const window = Window(todoui, title="Todos", size=(420px, 480px), animating=true)
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)
focus(todoui.firstchild)  # input

display(window)
