# Todo List
#
# Demonstrates the library's progressive-describe pipeline:
#
#     Data            -> SemanticUI       -> GeometricUI    -> ConcreteUI
#     Vector{TodoItem}  TodoApp/TodoRow/... Column/Row/Box... positioned rects
#
# Semantic nodes are created only in the data-to-semantic stage. Later
# `describe(::SemanticUI)` methods consume that semantic tree and lower it to
# geometry. That keeps the raw data type as the entry point: `describe(data)`.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/draw" ui draw
@use "../Interface/abstract" SemanticUI describe describe_children focus
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
  TodoItem("Ship the staged todo example", false)]

# --- semantic layer ---

@def mutable struct TodoApp <: SemanticUI
  todos::Vector{TodoItem} = TodoItem[]
  filter::Symbol = :all
end

@def mutable struct TodoTitle <: SemanticUI end
@def mutable struct TodoComposer <: SemanticUI end
@def mutable struct TodoFilters <: SemanticUI end

@def mutable struct FilterTab <: SemanticUI
  mode::Symbol = :all
end

@def mutable struct TodoList <: SemanticUI end

@def mutable struct TodoRow <: SemanticUI
  index::Int
end

@def mutable struct DeleteBtn <: SemanticUI end
@def mutable struct TodoFooter <: SemanticUI end

# --- semantic context helpers ---

todo_app(node::SemanticUI) = begin
  current = node
  while current !== nothing
    current isa TodoApp && return current
    current = current.parent
  end
  error("node is not inside a TodoApp")
end

todo_item(row::TodoRow) = todo_app(row).todos[row.index]
todo_list(app::TodoApp) = app.children[4]::TodoList
refresh_rows!(app::TodoApp) = begin
  list = todo_list(app)
  node = getfield(list, :firstchild)
  while node !== nothing
    next = node.nextsibling
    node.parent = nothing
    node.prevsibling = nothing
    node.nextsibling = nothing
    node = next
  end
  setfield!(list, :firstchild, nothing)
end

visible_indexes(app::TodoApp) =
  app.filter == :all ? collect(eachindex(app.todos)) :
  app.filter == :active ? filter(i -> !app.todos[i].done, eachindex(app.todos)) :
  filter(i -> app.todos[i].done, eachindex(app.todos))

filter_label(app::TodoApp, mode::Symbol) = begin
  total = length(app.todos)
  remaining = count(t -> !t.done, app.todos)
  mode == :all && return "All ($total)"
  mode == :active && return "Active ($remaining)"
  "Done ($(total - remaining))"
end

# --- describe: data -> SemanticUI ---

describe(items::Vector{TodoItem}) =
  TodoApp(todos=items,
    TodoTitle(),
    TodoComposer(TextInput(placeholder="What needs to be done?")),
    TodoFilters(),
    TodoList(),
    TodoFooter())

describe_children(::TodoFilters) =
  [FilterTab(mode=:all), FilterTab(mode=:active), FilterTab(mode=:done)]

describe_children(list::TodoList) =
  map(i -> TodoRow(index=i), visible_indexes(todo_app(list)))

describe_children(row::TodoRow) = begin
  item = todo_item(row)
  [
    Checkbox(checked=item.done, onchange=c -> begin
      item.done = c.checked
      refresh_rows!(todo_app(row))
    end),
    DeleteBtn()
  ]
end

# --- describe: SemanticUI -> GeometricUI ---

describe(::TodoTitle) =
  Row(width(grow=GrowType.Grow), height(42px),
    Box(width(grow=GrowType.Grow), height(34px),
      Text("Todos", size=24pt, weight=700, color=colorant"rgb(15,23,42)")),
    Box(width(94px), height(26px), Alignment.Center, radius(13px),
      background(colorant"rgb(226,232,240)"),
      Text("staged UI", size=10pt, weight=700, color=colorant"rgb(71,85,105)")))

describe(c::TodoComposer) = begin
  input = c.firstchild
  Row(width(grow=GrowType.Grow), height(44px),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      input))
end

describe(f::TodoFilters) = begin
  all, active, done = f.children
  Row(width(grow=GrowType.Grow), height(32px),
    all,
    Box(width(8px)),
    active,
    Box(width(8px)),
    done)
end

describe(tab::FilterTab) = begin
  app = todo_app(tab)
  active = app.filter == tab.mode
  Box(padding(7px, 12px), radius(7px),
      background(active ? colorant"rgb(37,99,235)" : colorant"white"),
      border(1px, :solid, active ? colorant"rgb(37,99,235)" : colorant"rgb(203,213,225)"),
    Text(filter_label(app, tab.mode), size=12pt, weight=700,
      color=active ? colorant"white" : colorant"rgb(51,65,85)"))
end

describe(list::TodoList) = begin
  rows = []
  for (i, row) in enumerate(list.children)
    i > 1 && push!(rows, Box(height(8px)))
    push!(rows, row)
  end
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), rows...)
end

describe(row::TodoRow) = begin
  checkbox, delete = row.children
  item = todo_item(row)
  Row(width(grow=GrowType.Grow), height(44px), padding(10px),
      radius(8px), background(colorant"white"),
      border(1px, :solid, colorant"rgb(226,232,240)"),
    checkbox,
    Box(width(12px)),
    Box(width(grow=GrowType.Grow), height(22px),
      Text(item.text, size=13pt,
      color=item.done ? colorant"rgb(148,163,184)" : colorant"rgb(30,41,59)")),
    delete)
end

describe(::DeleteBtn) =
  Box(width(24px), height(24px), Alignment.Center, radius(12px),
      background(colorant"rgb(241,245,249)"),
    Text("x", size=12pt, weight=700, color=colorant"rgb(148,163,184)"))

describe(footer::TodoFooter) = begin
  app = todo_app(footer)
  remaining = count(t -> !t.done, app.todos)
  label = remaining == 1 ? "1 item left" : "$remaining items left"
  Box(width(grow=GrowType.Grow), height(24px),
    Text(label, size=11pt, weight=600, color=colorant"rgb(100,116,139)"))
end

describe(app::TodoApp) = begin
  title, composer, filters, list, footer = app.children
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
    padding(24px), background(colorant"rgb(246,247,251)"),
    title,
    Box(height(14px)),
    composer,
    Box(height(18px)),
    filters,
    Box(height(14px)),
    list,
    footer)
end

# --- behaviour ---

composer_input(app::TodoApp) = (app.children[2]::TodoComposer).firstchild::TextInput

add_from_input!(app::TodoApp) = begin
  input = composer_input(app)
  text = strip(input.text)
  isempty(text) && return
  push!(app.todos, TodoItem(String(text), false))
  refresh_rows!(app)
  input.text = ""
  input.cursor = 0
  input.anchor = 0
end

onkey(b::DeleteBtn, ::KeyPress{Keys.mouse_left}) = begin
  row = b.parent::TodoRow
  row.parent isa TodoList || return
  list = row.parent::TodoList
  app = todo_app(list)
  list === todo_list(app) || return
  row.index in eachindex(app.todos) || return
  deleteat!(app.todos, row.index)
  refresh_rows!(app)
end

onkey(t::FilterTab, ::KeyPress{Keys.mouse_left}) = begin
  app = todo_app(t)
  app.filter = t.mode
  refresh_rows!(app)
end

onkey(app::TodoApp, ::KeyPress{Keys.enter}) = add_from_input!(app)

# --- entry: data -> SemanticUI -> Window ---

const todoui = describe(data)
const window = Window(todoui, title="Todos", size=(440px, 500px), animating=true)
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)
focus(composer_input(todoui))

display(window)
