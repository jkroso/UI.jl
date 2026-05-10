# Todo List
#
# North-star example for the downward UI.jl pipeline:
#
#     Data            -> SemanticUI       -> GeometricUI    -> ConcreteUI
#     Vector{TodoItem}  TodoApp/TodoRow/... Column/Row/Box... positioned rects
#
# `describe(data)` builds the editable semantic tree once. Event handlers
# mutate that tree in place — they never rebuild it. `integrate(app)`
# walks the tree to read fresh domain data back out.
#
# Filters do not destroy rows; they flip a `visible` flag on each row.
# Adds append a row, deletes detach one, "Clear completed" detaches a
# batch. Stable identity is the contract animation will rely on.

@use "github.com/jkroso/Prospects.jl" @def @property
@use "github.com/jkroso/Font.jl/units" em
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/draw" ui draw invalidate_layout!
@use "../Interface/abstract" SemanticUI WrapMode describe integrate focus add_child! detach!
@use "../Interface/Semantic/TextInput" TextInput
@use "../Interface/Semantic/Checkbox" Checkbox
@use Colors: @colorant_str

# --- data layer ------------------------------------------------------------

mutable struct TodoItem
  text::String
  done::Bool
end

const data = [
  TodoItem("Buy milk", false),
  TodoItem("Read the UI.jl docs", true),
  TodoItem("Ship the staged todo example", false),
  TodoItem("Reply to the launch email thread", false),
  TodoItem("Refactor the layout cache", true),
  TodoItem("Plan next week's offsite agenda", false),
  TodoItem("Audit error budgets for Q3", false),
  TodoItem("Renew the side-project domain", true),
  TodoItem("Sketch the new onboarding flow", false),
  TodoItem("File expense report from last trip", false),
  TodoItem("Pick out a birthday gift for Robin", false),
  TodoItem("Read the Skia clip op docs", true),
  TodoItem("Triage inbound issues on UI.jl", false)]

# --- semantic layer --------------------------------------------------------
#
# Every node here is editable state. Nothing here knows how it will be
# drawn — that's the next stage. The shape of this tree is fixed by
# `describe(::Vector{TodoItem})` below.

@def mutable struct TodoApp <: SemanticUI
  filter::Symbol = :all
  # While a remove animation is in progress we keep the same geometric
  # outer column across frames so the layout cache (keyed on objectid)
  # hits and only re-runs `position!`. Mutating `row.geo.offset_x`
  # in-place propagates the slide animation through the cached tree
  # without any allocation. `nothing` outside of animations.
  anim_geo::Any = nothing
end

@def mutable struct TodoTitle    <: SemanticUI end
@def mutable struct TodoComposer <: SemanticUI end
@def mutable struct TodoFilters  <: SemanticUI end

@def mutable struct FilterTab <: SemanticUI
  mode::Symbol = :all
end

# `scroll` caches the geometric Scroll viewport across frames.
# `describe(::TodoApp)` rebuilds the geometric tree every frame, but the
# Scroll node carries its own offset, so we must hand back the same
# instance each time or the scroll position resets on every redraw.
@def mutable struct TodoList <: SemanticUI
  scroll::Any = nothing
end
@def mutable struct TodoFooter <: SemanticUI end
@def mutable struct ClearCompleted <: SemanticUI
  enabled::Bool = false
end

@def mutable struct TodoRow <: SemanticUI
  text::String = ""
  done::Bool = false
  visible::Bool = true
  removing::Bool = false
  remove_t0::Float64 = 0.0
  # Cached geometric Row built on the first frame of the remove
  # animation. Subsequent frames mutate its `offset_x` (and `height`
  # during the collapse phase) so the cached geo tree stays valid.
  geo::Any = nothing
end

@def mutable struct TodoText <: SemanticUI
  editing::Bool = false
end

@def mutable struct DeleteBtn <: SemanticUI end

# Named accessors. The tree shape is fixed, so we expose children by
# role rather than ask every method to walk siblings.
@property TodoApp.title       = self.children[1]::TodoTitle
@property TodoApp.composer    = self.children[2]::TodoComposer
@property TodoApp.filter_bar  = self.children[3]::TodoFilters
@property TodoApp.list        = self.children[4]::TodoList
@property TodoApp.footer      = self.children[5]::TodoFooter
@property TodoComposer.input  = self.firstchild::TextInput
@property TodoFooter.clear    = self.firstchild::ClearCompleted
@property TodoRow.checkbox    = self.children[1]::Checkbox
@property TodoRow.todo_text   = self.children[2]::TodoText
@property TodoRow.delete_btn  = self.children[3]::DeleteBtn

# --- semantic helpers ------------------------------------------------------

row_visible(filter::Symbol, done::Bool) =
  filter == :all || (filter == :active && !done) || (filter == :done && done)

# Delete animation: the row slides off to the left, then collapses its
# vertical space, then detaches from the list. The slide and collapse run
# back-to-back so the row visibly leaves before the column closes the gap.
const REMOVE_SLIDE_MS    = 220.0
const REMOVE_COLLAPSE_MS = 180.0
const REMOVE_SLIDE_PX    = 500px

ease_out_quad(t::Float64) = 1 - (1 - t)^2

remove_progress(row) = begin
  elapsed_ms = (time() - row.remove_t0) * 1000
  slide    = clamp(elapsed_ms / REMOVE_SLIDE_MS, 0.0, 1.0)
  collapse = clamp((elapsed_ms - REMOVE_SLIDE_MS) / REMOVE_COLLAPSE_MS, 0.0, 1.0)
  done     = elapsed_ms >= REMOVE_SLIDE_MS + REMOVE_COLLAPSE_MS
  (slide=slide, collapse=collapse, done=done)
end

start_remove!(row) = begin
  row.removing && return
  row.removing = true
  row.remove_t0 = time()
  # Force the next frame to rebuild the cached outer geo so this row's
  # describe runs (and caches its row.geo for in-place mutation).
  invalidate_app_geo!(row)
end

invalidate_app_geo!(row::TodoRow) = begin
  list = row.parent
  list isa TodoList || return
  app = list.parent
  app isa TodoApp && (app.anim_geo = nothing)
  nothing
end
invalidate_app_geo!(app::TodoApp) = (app.anim_geo = nothing; nothing)

apply_filter!(app::TodoApp) = begin
  for row in app.list.children
    row.visible = row_visible(app.filter, row.done)
  end
  app
end

count_total(app::TodoApp)     = length(app.list.children)
count_done(app::TodoApp)      = count(r -> r.done,  app.list.children)
count_remaining(app::TodoApp) = count(r -> !r.done, app.list.children)

filter_label(app::TodoApp, mode::Symbol) =
  mode == :all    ? "All ($(count_total(app)))"        :
  mode == :active ? "Active ($(count_remaining(app)))" :
                    "Done ($(count_done(app)))"

# Mirrors a checkbox toggle into the row's `done` field and re-evaluates
# whether this row is visible under the current filter.
row_checked!(c::Checkbox) = begin
  row = c.parent::TodoRow
  app = (row.parent::TodoList).parent::TodoApp
  row.done = c.checked
  row.visible = row_visible(app.filter, row.done)
  invalidate_app_geo!(app)
end

# A row carrying a copy of the domain item's data. The row owns its text
# and its done flag; mutating those fields is what editing the UI means.
TodoRow(item::TodoItem) =
  TodoRow(
    Checkbox(checked=item.done, onchange=row_checked!),
    TodoText(),
    DeleteBtn();
    text=String(item.text),
    done=item.done)

TodoList(items::Vector{TodoItem}) =
  TodoList((TodoRow(item) for item in items)...)

# --- describe: data -> SemanticUI -----------------------------------------
#
# The only place semantic nodes are created from data. Everything below
# this line consumes existing tree nodes — it never instantiates new
# semantic ones inside a `describe(::SemanticUI)` body.

describe(items::Vector{TodoItem}) =
  TodoApp(
    TodoTitle(),
    TodoComposer(TextInput(placeholder="What needs doing?")),
    TodoFilters(
      FilterTab(mode=:all),
      FilterTab(mode=:active),
      FilterTab(mode=:done)),
    TodoList(items),
    TodoFooter(ClearCompleted()))

# --- integrate: SemanticUI -> data ----------------------------------------
#
# The upward half of the pipeline. `integrate(app)` is called by the host
# program when it wants the current edited data — it doesn't walk
# geometry, it walks the semantic tree the user has been mutating.

integrate(row::TodoRow)   = TodoItem(String(row.text), row.done)
integrate(list::TodoList) = TodoItem[integrate(r::TodoRow) for r in list.children]
integrate(app::TodoApp)   = integrate(app.list)

# --- visual constants -----------------------------------------------------

const C_BG       = colorant"rgb(247,248,251)"
const C_PANEL    = colorant"white"
const C_BORDER   = colorant"rgb(226,232,240)"
const C_TEXT     = colorant"rgb(15,23,42)"
const C_DIM      = colorant"rgb(100,116,139)"
const C_MUTED    = colorant"rgb(148,163,184)"
const C_ACCENT   = colorant"rgb(37,99,235)"
const C_DEL_BG   = colorant"rgb(241,245,249)"

# --- describe: SemanticUI -> GeometricUI ----------------------------------
#
# These methods consume the existing semantic tree and return a geometric
# one. Semantic children placed inside geometric containers are lowered
# implicitly via `convert(GeometricUI, ::SemanticUI)` — there is no
# explicit `describe!` call anywhere in this file.

describe(app::TodoApp) = begin
  has_anim, structure_changed = tick_animations!(app)
  if has_anim && app.anim_geo !== nothing && !structure_changed
    return app.anim_geo
  end
  app.anim_geo = nothing
  title, composer, _filters, list, footer = app.children
  geo = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
               padding(24px), background(C_BG),
    title,
    Box(height(14px)),
    composer,
    Box(height(14px)),
    list,
    Box(height(14px)),
    footer)
  has_anim && (app.anim_geo = geo)
  geo
end

# Per-frame animation tick. Detaches finished rows, mutates in-progress
# rows' `offset_x` (and `height` during collapse) directly on the cached
# geo so the layout cache can keep hitting. Returns whether any
# animation is in progress and whether the row structure changed (which
# forces a rebuild of the cached outer geo).
tick_animations!(app::TodoApp) = begin
  has_anim = false
  structure_changed = false
  needs_relayout = false
  for child in collect(app.list.children)
    r = child::TodoRow
    r.removing || continue
    prog = remove_progress(r)
    if prog.done
      detach!(r)
      structure_changed = true
      continue
    end
    has_anim = true
    if r.geo !== nothing
      r.geo.offset_x = -REMOVE_SLIDE_PX * ease_out_quad(prog.slide)
      if prog.collapse > 0
        # Height changes can't be picked up by `position!` alone — the
        # ConcreteRect's height was set during fit!, so we need a fresh
        # layout pass for the collapse phase.
        r.geo.height = Height(preferred=44px * (1 - prog.collapse))
        needs_relayout = true
      end
    end
  end
  (structure_changed || needs_relayout) && invalidate_layout!(window)
  has_anim, structure_changed
end

describe(t::TodoTitle) = begin
  app = t.parent::TodoApp
  Row(width(grow=GrowType.Grow), height(36px), Alignment.Center,
    Box(height(28px),
      Text("Todos", size=22pt, weight=700, color=C_TEXT, wrap=WrapMode.none)),
    Box(width(grow=GrowType.Grow)),
    app.filter_bar)
end

describe(c::TodoComposer) = Row(width(grow=GrowType.Grow), height(44px), c.input)

describe(f::TodoFilters) = begin
  all, active, done = f.children
  Row(width(grow=GrowType.None), height(32px),
    all, Box(width(6px)), active, Box(width(6px)), done)
end

describe(tab::FilterTab) = begin
  app = (tab.parent::TodoFilters).parent::TodoApp
  active = app.filter == tab.mode
  Box(width(grow=GrowType.None), padding(5px, 9px), radius(6px),
      background(active ? C_ACCENT : C_PANEL),
      border(1px, :solid, active ? C_ACCENT : C_BORDER),
    Text(filter_label(app, tab.mode), size=10pt, weight=700,
         wrap=WrapMode.none,
         color=active ? C_PANEL : C_TEXT))
end

describe(list::TodoList) = begin
  # An exiting row stays in the list (and visible) until its animation
  # completes, even if the active filter would otherwise hide it.
  # Detaching finished animations is handled by `tick_animations!`.
  visible_rows = TodoRow[r for r in list.children
                         if (r::TodoRow).visible || (r::TodoRow).removing]
  isempty(visible_rows) && return empty_state(list)
  spaced = Any[]
  for (i, row) in enumerate(visible_rows)
    i > 1 && push!(spaced, Box(height(8px)))
    push!(spaced, row)
  end
  inner = Column(width(grow=GrowType.Grow), spaced...)

  # Reuse the cached Scroll so its offset survives across frames. Each
  # frame replaces the inner Column (the rows themselves are semantic
  # nodes — the geometric column wrapping them is rebuilt). Detach the
  # Scroll itself before returning so sibling pointers from the previous
  # frame's outer Column don't leak into this frame's tree.
  scroll = list.scroll
  if scroll === nothing
    scroll = Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                    padding(8px), radius(8px),
                    background(C_PANEL), border(1px, :solid, C_BORDER))
    list.scroll = scroll
  end
  for child in collect(scroll.children)
    detach!(child)
  end
  add_child!(scroll, inner)
  detach!(scroll)
  scroll
end

empty_state(list::TodoList) = begin
  app = list.parent::TodoApp
  msg = count_total(app) == 0       ? "Add your first todo above." :
        app.filter == :active        ? "Nothing left to do."        :
        app.filter == :done          ? "No completed items yet."    :
                                       "Nothing here."
  Box(width(grow=GrowType.Grow), height(64px),
      Alignment.Center, radius(8px),
      background(C_PANEL), border(1px, :solid, C_BORDER),
    Text(msg, size=12pt, weight=500, color=C_MUTED, align=TextAlign.Center))
end

describe(row::TodoRow) = begin
  prog = row.removing ? remove_progress(row) : nothing
  h    = prog === nothing ? 44px : 44px * (1 - prog.collapse)
  ox   = prog === nothing ? 0px : -REMOVE_SLIDE_PX * ease_out_quad(prog.slide)
  geo = Row(width(grow=GrowType.Grow), height(h), padding(10px),
            radius(8px), background(C_PANEL), Alignment.Center,
            border(1px, :solid, C_BORDER),
            offset_x=ox,
    Box(width(2em), row.checkbox),
    Box(width(12px)),
    row.todo_text,
    Box(width(12px)),
    row.delete_btn)
  # Hand the geo back to the row so subsequent frames can mutate it
  # without rebuilding the whole tree.
  row.removing && (row.geo = geo)
  geo
end

describe(t::TodoText) = begin
  row = t.parent::TodoRow
  inner = t.editing ?
    t.firstchild::TextInput :
    Text(isempty(row.text) ? " " : row.text,
         size=13pt, weight=500, wrap=WrapMode.none,
         color=row.done ? C_MUTED : C_TEXT)
  Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
      Alignment.Center, inner)
end

describe(::DeleteBtn) =
  Box(width(24px), height(24px), Alignment.Center, radius(12px),
      background(C_DEL_BG),
    Text("×", size=14pt, weight=700, color=C_MUTED, wrap=WrapMode.none))

describe(footer::TodoFooter) = begin
  app = footer.parent::TodoApp
  remaining = count_remaining(app)
  clear = footer.clear
  clear.enabled = count_done(app) > 0
  label = remaining == 1 ? "1 item left" : "$remaining items left"
  Row(width(grow=GrowType.Grow), height(24px), Alignment.Center,
    Box(height(18px),
      Text(label, size=11pt, weight=600, color=C_DIM, wrap=WrapMode.none)),
    Box(width(grow=GrowType.Grow)),
    clear)
end

describe(c::ClearCompleted) =
  Box(padding(2px, 4px),
    Text("Clear completed", size=11pt, weight=700, wrap=WrapMode.none,
         color=c.enabled ? C_ACCENT : C_MUTED))

# --- behaviour -------------------------------------------------------------

add_from_input!(app::TodoApp) = begin
  input = app.composer.input
  text = strip(input.text)
  isempty(text) && return
  add_child!(app.list, TodoRow(
    Checkbox(onchange=row_checked!),
    TodoText(),
    DeleteBtn();
    text=String(text),
    done=false,
    visible=row_visible(app.filter, false)))
  input.text = ""
  input.cursor = 0
  input.anchor = 0
  invalidate_app_geo!(app)
end

clear_completed!(app::TodoApp) = begin
  for row in app.list.children
    (row::TodoRow).done && start_remove!(row)
  end
end

# Each row's text is editable in place: clicking the text swaps in a
# TextInput as a child of TodoText, focuses it, and re-renders. Enter
# saves, Escape cancels. Saving copies the editor's text back into the
# row, then detaches the editor — so the row tree returns to its
# minimal three-child shape.

start_edit!(t::TodoText) = begin
  t.editing && return
  app = ((t.parent::TodoRow).parent::TodoList).parent::TodoApp
  ed = active_editor(app)
  ed === nothing || ed === t || save_edit!(ed)
  row = t.parent::TodoRow
  editor = TextInput(text=String(row.text),
                     cursor=length(row.text),
                     anchor=length(row.text))
  add_child!(t, editor)
  t.editing = true
  focus(editor)
  invalidate_app_geo!(app)
end

save_edit!(t::TodoText) = begin
  t.editing || return
  editor = t.firstchild::TextInput
  row = t.parent::TodoRow
  text = strip(editor.text)
  isempty(text) || (row.text = String(text))
  detach!(editor)
  t.editing = false
  return_focus_to_composer(t)
  invalidate_app_geo!(row)
end

cancel_edit!(t::TodoText) = begin
  t.editing || return
  editor = t.firstchild::TextInput
  detach!(editor)
  t.editing = false
  return_focus_to_composer(t)
  invalidate_app_geo!(t.parent::TodoRow)
end

return_focus_to_composer(t::TodoText) = begin
  app = ((t.parent::TodoRow).parent::TodoList).parent::TodoApp
  focus(app.composer.input)
end

active_editor(app::TodoApp) = begin
  for row in app.list.children
    tt = (row::TodoRow).todo_text
    tt.editing && return tt
  end
  nothing
end

# --- event handlers -------------------------------------------------------
#
# Events bubble up through SemanticUI ancestors. We use the tree shape
# to disambiguate Enter: the composer's Enter handler lives on
# TodoComposer, and the row editor's Enter handler lives on TodoText —
# so Enter from the composer never reaches a row, and Enter from a row
# editor never reaches the composer.

onkey(b::DeleteBtn, ::KeyPress{Keys.mouse_left}) =
  start_remove!(b.parent::TodoRow)

onkey(t::FilterTab, ::KeyPress{Keys.mouse_left}) = begin
  app = (t.parent::TodoFilters).parent::TodoApp
  app.filter = t.mode
  apply_filter!(app)
  invalidate_app_geo!(app)
end

onkey(t::TodoText, ::KeyPress{Keys.mouse_left}) = start_edit!(t)
onkey(t::TodoText, ::KeyPress{Keys.enter})       = save_edit!(t)

onkey(c::TodoComposer, ::KeyPress{Keys.enter}) =
  add_from_input!(c.parent::TodoApp)

onkey(c::ClearCompleted, ::KeyPress{Keys.mouse_left}) = begin
  c.enabled || return
  clear_completed!((c.parent::TodoFooter).parent::TodoApp)
end

# Escape cancels an in-flight edit if there is one; otherwise closes.
onkey(w::Window, ::KeyPress{Keys.escape}) = begin
  app = w.ui
  if app isa TodoApp
    ed = active_editor(app)
    ed === nothing || return cancel_edit!(ed)
  end
  close(w)
end

# --- entry: data -> SemanticUI -> Window ----------------------------------

const todoui = describe(data)
const window = Window(todoui, title="Todos", size=(440px, 520px), animating=true)
focus(todoui.composer.input)

display(window)
