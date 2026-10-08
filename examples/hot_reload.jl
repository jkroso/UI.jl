# Run an example so that the window uses your changes as soon as you save them.
# What the window shows stays as it was, so Finder stays in the same folder with
# the same files selected.
#
#     julia --project=. examples/hot_reload.jl examples/26_finder.jl ~/Desktop
#
# The arguments after the example go to the example. It watches the example's
# files and UI.jl's. The example needs a block at the end that opens its window
# when it's run on its own, as Finder, Disk Usage and the Clay website have:
#
#     if abspath(PROGRAM_FILE) == @__FILE__
#       open_finder(ARGS)
#     end
#
# When you save a file:
#   - Only the parts of it that you changed run again, so the caches at the top
#     of a file keep what's in them. A line that uses a name you changed runs
#     again too, here and in the files that use this one.
#   - If you change a struct's fields, the window can't use the new code, since
#     what it shows was made with the old fields. So the file and the files that
#     use it run again from the top, and the window opens again in the same place.
#   - If the file doesn't parse, none of it changes until you fix it.
#   - An error while the window draws or handles input is printed once, and the
#     window keeps its last picture. Save a fix and it carries on.
#   - A method you delete stays until you restart.
#
# Kip loads each file from its source here, not from its compiled caches, so that
# each file has a module to load changes into. That makes starting slower.

const started = time()
using Kip, Logging
import GLFW

isempty(ARGS) && (println(stderr, "Give it an example to run: julia --project=. examples/hot_reload.jl examples/26_finder.jl"); exit(1))
const entry = realpath(popfirst!(ARGS))
ENV["KIP_FROZEN"] = "1"

@use "github.com/jkroso/MiniFB.jl" => MiniFB
@use "../Interface/draw" invalidate_layout!

# The window's thread waits in GLFW for input, and Julia's timers don't run while
# it does. So the watcher needs a thread of its own.
Threads.threadpool() == :default && Threads.nthreads(:default) < 2 &&
  error("Hot reload needs a second thread to watch files. Run Julia without -t 1.")

"A file Kip loaded, the module it's in, and the code in it that last ran"
mutable struct Source
  path::String
  mod::Module
  mtime::Float64
  exprs::Vector{Tuple{LineNumberNode,Any}}
end

const sources = Dict{String,Source}()
# The watcher reads `sources` on its own thread
const watching = ReentrantLock()
# Set by the watcher when a file changes. The next frame loads it.
const saved = Threads.Atomic{Bool}(false)
# Set when the window has to open again
const restart = Ref(false)

short(path) = startswith(path, pwd()) ? relpath(path) : Base.contractuser(path)

"Print a line now. When the output goes to a file, Julia would hold it back."
say(io::IO, xs...) = (println(io, xs...); flush(io))
say(xs...) = say(stdout, xs...)

# --- reading code ------------------------------------------------------------

"Each top-level expression in the file at `path`, with the line it starts on"
top_level(path) = begin
  code = Meta.parseall(read(path, String), filename=path)
  exprs = Tuple{LineNumberNode,Any}[]
  line = LineNumberNode(1, Symbol(path))
  for ex in code.args
    if ex isa LineNumberNode
      line = ex
    else
      problem = parse_error(ex)
      problem === nothing || throw(problem)
      push!(exprs, (line, ex))
    end
  end
  exprs
end

parse_error(ex::Expr) =
  if ex.head in (:error, :incomplete)
    e = isempty(ex.args) ? nothing : ex.args[1]
    e isa Exception ? e : ErrorException(string(something(e, "incomplete code")))
  else
    for a in ex.args
      e = parse_error(a)
      e === nothing || return e
    end
    nothing
  end
parse_error(_) = nothing

"`ex` without its line numbers, to tell whether it changed or just moved"
bare(ex::Expr) =
  ex.head == :macrocall ? Expr(:macrocall, ex.args[1], nothing, map(bare, ex.args[3:end])...) :
                          Expr(ex.head, (bare(a) for a in ex.args if !(a isa LineNumberNode))...)
bare(x) = x

"The names that `ex` defines, like a function's or a struct's"
defines(ex) = begin
  names = Set{Symbol}()
  name(x) =
    if x isa Symbol
      push!(names, x)
    elseif x isa QuoteNode
      name(x.value)
    elseif Meta.isexpr(x, :.)
      name(x.args[end])
    elseif Meta.isexpr(x, (:call, :where, :(::), :curly, :<:)) && !isempty(x.args)
      name(x.args[1])
    end
  if Meta.isexpr(ex, (:function, :(=), :abstract, :primitive))
    name(ex.args[1])
  elseif Meta.isexpr(ex, :struct)
    name(ex.args[2])
  elseif Meta.isexpr(ex, (:const, :global, :block))
    foreach(a -> union!(names, defines(a)), ex.args)
  elseif Meta.isexpr(ex, :macrocall)
    # Docstrings, @kwdef and the like wrap a definition. The names an @use line
    # brings in are found by checking which values changed.
    foreach(a -> a isa Expr && union!(names, defines(a)), ex.args[3:end])
  end
  names
end

"Whether `ex` does something when it runs, rather than define a function or a type"
statement(ex) =
  !(Meta.isexpr(ex, (:function, :macro, :struct, :abstract, :primitive, :module, :macrocall,
                     :using, :import, :export, :public)) || Meta.isexpr(ex, :(=)) && signature(ex.args[1]))
signature(x) = Meta.isexpr(x, :call) || Meta.isexpr(x, (:where, :(::))) && signature(x.args[1])

mentions(ex::Symbol, names) = ex in names
mentions(ex::Expr, names) = any(a -> mentions(a, names), ex.args)
mentions(_, names) = false

"The watched file that `ex`, an @use line in `src`, loads"
use_target(src, ex) = begin
  Meta.isexpr(ex, :macrocall) && ex.args[1] === Symbol("@use") && length(ex.args) >= 3 || return nothing
  p = ex.args[3]
  Meta.isexpr(p, :call) && p.args[1] === :(=>) && (p = p.args[2])
  Meta.isexpr(p, :...) && (p = p.args[1])
  p isa String && (startswith(p, ".") || startswith(p, "/")) || return nothing
  file = try
    first(Kip.complete(startswith(p, "/") ? p : normpath(dirname(src.path), p)))
  catch
    return nothing
  end
  haskey(sources, file) ? file : nothing
end

"Every watched file, each one after the files it uses"
load_order() = begin
  order, done = Source[], Set{String}()
  visit(s) = begin
    s.path in done && return
    push!(done, s.path)
    for (_, ex) in s.exprs
      p = use_target(s, ex)
      p === nothing || visit(sources[p])
    end
    push!(order, s)
  end
  foreach(visit, sort!(collect(values(sources)), by=s -> s.path))
  order
end

"Watch each file Kip has loaded that you can change. Kip's copies of GitHub packages never change."
track!() =
  for (path, mod) in Kip.modules
    isabspath(path) && isfile(path) && !startswith(path, Kip.refs) && !haskey(sources, path) || continue
    exprs = try top_level(path) catch; continue end
    s = Source(path, mod, mtime(path), exprs)
    lock(() -> sources[path] = s, watching)
  end

# --- running code ------------------------------------------------------------

"Leaves out the warning Julia gives when a docstring is replaced"
struct Quiet <: AbstractLogger
  next::AbstractLogger
end
Logging.min_enabled_level(l::Quiet) = Logging.min_enabled_level(l.next)
Logging.shouldlog(l::Quiet, level, _module, args...) = _module !== Base.Docs && Logging.shouldlog(l.next, level, _module, args...)
Logging.handle_message(l::Quiet, args...; kwargs...) = Logging.handle_message(l.next, args...; kwargs...)
Logging.catch_exceptions(l::Quiet) = Logging.catch_exceptions(l.next)

"Run `ex` in `src`'s module, as if Julia were including the file. Return whether it worked."
run!(src, line, ex) =
  try
    with_logger(Quiet(current_logger())) do
      task_local_storage(:SOURCE_PATH, src.path) do
        Core.eval(src.mod, Expr(:toplevel, line, ex))
      end
    end
    true
  catch e
    report("$(short(src.path)):$(line.line) failed", e, catch_backtrace())
    false
  end

"Each name in `m` and its value now. New code only sees new values, hence invokelatest."
values_in(m) = Base.invokelatest() do
  Dict{Symbol,Any}(n => getglobal(m, n) for n in names(m, all=true) if isdefinedglobal(m, n))
end

"""
Run the top-level expressions in `src` that `picks` chooses. Then run each later
statement that uses a name they defined or changed, or a name in `given`.

Julia 1.13 doesn't always drop the code it compiled with a constant's old value.
Code that picks between constants, like `use!(dark ? DARK : LIGHT)`, keeps the
old ones. So when a constant changes, each definition that uses it runs again too.
"""
rerun!(src, picks, given=Set{Symbol}()) = begin
  before = values_in(src.mod)
  changed() = Set(n for (n, v) in values_in(src.mod) if haskey(before, n) && before[n] !== v)
  hot = Set{Symbol}(given)
  ran = falses(length(src.exprs))
  run(i) = begin
    line, ex = src.exprs[i]
    run!(src, line, ex)
    ran[i] = true
    union!(hot, defines(ex), changed())
  end
  picked = also = 0
  for (i, (_, ex)) in enumerate(src.exprs)
    if picks[i]
      picked += 1
      run(i)
    elseif statement(ex) && mentions(ex, hot)
      also += 1
      run(i)
    end
  end
  constants = changed()
  for (i, (_, ex)) in enumerate(src.exprs)
    ran[i] || statement(ex) || !mentions(ex, constants) || (also += 1; run(i))
  end
  (; before, hot, changed=changed(), picked, also)
end

plural(n, one, many) = n == 1 ? "1 $one" : "$n $many"

"Run what changed in `src` since it last ran, and what uses it"
update!(src) = begin
  exprs = try
    top_level(src.path)
  catch e
    report("$(short(src.path)) doesn't parse, so none of it changed", e, nothing)
    return
  end
  # An editor that writes a file in two steps can leave it empty for a moment
  isempty(exprs) && !isempty(src.exprs) && return
  left = Dict{Any,Int}()
  foreach(((_, ex),) -> (k = bare(ex); left[k] = get(left, k, 0) + 1), src.exprs)
  picks = map(exprs) do (_, ex)
    k = bare(ex)
    n = get(left, k, 0)
    n > 0 && (left[k] = n - 1)
    n == 0
  end
  src.exprs = exprs
  any(picks) || return say("$(short(src.path)): no code changed")
  t = time()
  r = rerun!(src, picks)
  say("Reloaded $(short(src.path)) in $(round(time() - t, digits=2)) s: ", plural(r.picked, "change", "changes"),
      r.also == 0 ? "" : ", and " * plural(r.also, "line that uses them", "lines that use them"))
  structs = [n for n in r.changed if r.before[n] isa Type]
  isempty(structs) ? spread!(src, r) : reload_users!(src, structs)
end

"""
Run again the parts of the files that use `src` that used a name that changed
in it: their @use lines for `src`, then the statements that use those names.
"""
spread!(src, r, seen=Set([src.path])) =
  for g in values(sources)
    (g.path in seen || !any(((_, ex),) -> use_target(g, ex) == src.path, g.exprs)) && continue
    push!(seen, g.path)
    picks = [!isempty(r.changed) && use_target(g, ex) == src.path for (_, ex) in g.exprs]
    r2 = rerun!(g, picks, r.hot)
    r2.picked + r2.also == 0 && continue
    say("Reloaded $(short(g.path)): ", plural(r2.picked + r2.also, "line", "lines"), " that use $(short(src.path))")
    structs = [n for n in r2.changed if r2.before[n] isa Type]
    isempty(structs) || return reload_users!(g, structs)
    spread!(g, (; changed=r2.changed, hot=union(setdiff(r2.hot, r.hot), r2.changed)), seen)
  end

"""
A struct in `src` has new fields. What the window shows was made with the old
struct, and the methods in the files that use it are for the old struct too. So
run all of `src` and of each file that uses it, then open the window again.
"""
reload_users!(src, structs) = begin
  closed[] = time()
  say("The fields of ", join(structs, ", ", " and "), " changed. Running ", short(src.path),
          " and the files that use it again, then opening the window again.")
  affected = Set([src.path])
  order = load_order()
  for s in order
    any(((_, ex),) -> use_target(s, ex) in affected, s.exprs) && push!(affected, s.path)
  end
  for s in order
    s.path in affected || continue
    rerun!(s, trues(length(s.exprs)))
    # Kip runs a file's __init__ after it loads it
    Base.invokelatest(isdefinedglobal, s.mod, :__init__) && Base.invokelatest(getglobal(s.mod, :__init__))
  end
  restart!()
end

"Load the files that changed since they last ran"
reload!() = begin
  saved[] = false
  last_problem[] = ""
  stale = [s for s in load_order() if isfile(s.path) && mtime(s.path) != s.mtime]
  for s in stale
    t = mtime(s.path)
    lock(() -> s.mtime = t, watching)
    update!(s)
    restart[] && break
  end
  track!()
  foreach(w -> Base.invokelatest(invalidate_layout!, w), shown)
end

# --- the window --------------------------------------------------------------

"Print an error, and the places in the watched files it went through"
report(what, e, bt) = begin
  say(stderr, what, ":\n  ", replace(sprint(showerror, e), "\n" => "\n  "))
  bt === nothing && return
  frames = unique(f -> (f.file, f.line), [f for f in stacktrace(bt) if haskey(sources, string(f.file))])
  for f in first(frames, 5)
    say(stderr, "  in ", f.func, " at ", short(string(f.file)), ":", f.line)
  end
end

# The window would print the same error for every frame
const last_problem = Ref("")
window_error(what, e, bt) = begin
  msg = sprint(showerror, e)
  msg == last_problem[] && return
  last_problem[] = msg
  report(what, e, bt)
end

const shown = Base.IdSet{Any}()
# Where the window was when it closed to open again, and when the files started to run again
const place = Ref{Any}(nothing)
const closed = Ref(0.0)

const setters = (GLFW.SetKeyCallback, GLFW.SetMouseButtonCallback, GLFW.SetCursorPosCallback, GLFW.SetScrollCallback,
                 GLFW.SetDropCallback, GLFW.SetFramebufferSizeCallback, GLFW.SetWindowSizeCallback, GLFW.SetWindowPosCallback)

"""
Catch the errors from the input handlers that MiniFB gave GLFW. An error would
otherwise end the window's loop and close it.
"""
guard_input!(w) =
  for set in setters
    inner = Ref{Any}(nothing)
    inner[] = set(w.glfw[1], (args...) -> try
      inner[](args...)
    catch e
      window_error("The window couldn't handle that input", e, catch_backtrace())
    end)
    inner[] === nothing && set(w.glfw[1], nothing)
  end

restart!() = begin
  restart[] = true
  for w in shown
    place[] = (GLFW.GetWindowPos(w.glfw[1]), GLFW.GetWindowSize(w.glfw[1]))
    close(w)
  end
  GLFW.PostEmptyEvent()
end

"""
MiniFB's loop calls this for each frame. Load the files that changed first, and
print an error from drawing rather than end the loop.
"""
MiniFB.redraw(w::MiniFB.Window) = begin
  if !(w in shown)
    push!(shown, w)
    guard_input!(w)
    if place[] !== nothing
      GLFW.SetWindowPos(w.glfw[1], place[][1]...)
      GLFW.SetWindowSize(w.glfw[1], place[][2]...)
      place[] = nothing
      say("The window opened again in $(round(time() - closed[], digits=1)) s")
    end
  end
  saved[] && reload!()
  restart[] && return
  try
    invoke(MiniFB.redraw, Tuple{MiniFB.AbstractWindow}, w)
  catch e
    window_error("The window couldn't draw, so it shows its last picture until you save a fix", e, catch_backtrace())
  end
end

"The block in `src` that opens its window when the file is run on its own"
opener(src) = begin
  for (line, ex) in src.exprs
    Meta.isexpr(ex, :if) && occursin("PROGRAM_FILE", string(ex.args[1])) && return (line, ex.args[2])
  end
  error("$(short(src.path)) has no `if abspath(PROGRAM_FILE) == @__FILE__` block to open its window")
end

# --- start -------------------------------------------------------------------

say("Loading $(short(entry))…")
Kip.require(entry, dirname(entry))
track!()
say("Loaded in $(round(Int, time() - started)) s. Watching $(length(sources)) files. Save one and the window uses it.")

"""
Sleep for `n` hundredths of a second. The watcher's thread is often the only one
in the default pool, so it shares it with tasks like the workers in Disk Usage's
scan. It sleeps in short steps and lets them run in between, or they'd never
run. The gc_safe sleep lets Julia collect garbage meanwhile.
"""
nap(n) = for _ in 1:n
  @ccall gc_safe=true usleep(10_000::Cuint)::Cint
  yield()
end

# Checking a file's time is quick, so the watcher can look 4 times a second
Threads.@spawn :default while true
  nap(25)
  lock(watching) do
    any(s -> mtime(s.path) != s.mtime, values(sources))
  end || continue
  # Editors can write a file in more than one step. Give them time to finish.
  nap(5)
  saved[] = true
  # Wakes the window's loop from its wait, so it draws a frame
  GLFW.PostEmptyEvent()
end

while true
  restart[] = false
  ok = run!(sources[entry], opener(sources[entry])...)
  empty!(shown)
  restart[] && continue
  ok && break
  say(stderr, "Save a fix and the example starts again.")
  while !saved[]
    sleep(0.25)
  end
  reload!()
end
