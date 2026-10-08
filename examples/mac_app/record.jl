# Recording the calls a trimmed app needs. start.jl includes this file.
#
# A trimmed app only has the methods that `main` can be seen to call before the
# app runs. UI.jl picks most of its methods while the app runs: which `describe`
# and `draw` for each kind of node, which `onkey` for each key, and so on. So
# build.jl first runs the app with `--record`, while Julia writes down each of
# those calls (Julia's `--trace-dispatch` option). Then the trimmed build marks
# each call it wrote down as one to keep, with `keep_recorded`.
#
# With `--record` the app runs its warm up, then opens its real window and sends
# it every kind of input that GLFW can send: each key, each mouse button, moves,
# scrolling, a dropped folder and resizing. The input goes in through GLFW's own
# callback wrappers, so it takes the same path as input from a person does.

"""
Open a real window with `open_app()`, then call `drive(window)` with its GLFW
window, and close the window when `drive` returns. Another thread wakes the
window's loop every few milliseconds, so `drive` keeps running while the window
has nothing to draw.
"""
record_window(drive, open_app) = begin
  awake = Threads.Atomic{Bool}(true)
  # `sleep` would wait on a timer that the window's thread runs, and that thread
  # is waiting for an event, so this sleeps the plain way. Then it lets Julia's
  # garbage collector run, which would otherwise wait for this loop forever.
  waker = Threads.@spawn :default while awake[]
    GLFW.PostEmptyEvent()
    Libc.systemsleep(0.005)
    GC.safepoint()
  end
  driver = @async begin
    window = GLFW.GetCurrentContext()
    while window.handle == C_NULL
      sleep(0.01)
      window = GLFW.GetCurrentContext()
    end
    try
      drive(window)
    finally
      GLFW.SetWindowShouldClose(window, true)
    end
  end
  open_app()
  awake[] = false
  wait(waker)
  fetch(driver)
end

"Let the window draw a few frames"
settle_window(n=5) = for _ in 1:n; sleep(0.02) end

move_to(window, x, y) = GLFW._CursorPosCallbackWrapper(window, Float64(x), Float64(y))

"Press and release `button` with the pointer at `x`, `y`"
click_at(window, x, y, button=GLFW.MOUSE_BUTTON_LEFT) = begin
  move_to(window, x, y)
  GLFW._MouseButtonCallbackWrapper(window, button, GLFW.PRESS, Cint(0))
  GLFW._MouseButtonCallbackWrapper(window, button, GLFW.RELEASE, Cint(0))
  settle_window(1)
end

"Hold down `mods`, press and release `key`, then let go of `mods`"
press_keys(window, key, mods...) = begin
  foreach(m -> GLFW._KeyCallbackWrapper(window, m, Cint(0), GLFW.PRESS, Cint(0)), mods)
  GLFW._KeyCallbackWrapper(window, key, Cint(0), GLFW.PRESS, Cint(0))
  GLFW._KeyCallbackWrapper(window, key, Cint(0), GLFW.RELEASE, Cint(0))
  foreach(m -> GLFW._KeyCallbackWrapper(window, m, Cint(0), GLFW.RELEASE, Cint(0)), reverse(mods))
  settle_window(2)
end

"""
Send `window` every kind of input GLFW can send it. The pointer moves to each of
`points`, and scrolls at each one. `drop` is a folder to drop on the window.

A click lands where the pointer really is, since UI.jl asks GLFW for that when a
button goes down, so each button is only clicked once. The app's warm up has
already clicked each thing in the window, through the same methods.
"""
send_every_input(window; points, drop) = begin
  settle_window()
  for (x, y) in points
    move_to(window, x, y)
    GLFW._ScrollCallbackWrapper(window, 0.0, -2.0)
    GLFW._ScrollCallbackWrapper(window, 0.0, 2.0)
    settle_window(1)
  end
  # MiniFB has no name for some of GLFW's buttons and keys
  for button in instances(GLFW.MouseButton)
    try click_at(window, last(points)..., button) catch end
  end
  # Each key, held down long enough to repeat
  for key in instances(GLFW.Key), action in (GLFW.PRESS, GLFW.REPEAT, GLFW.RELEASE)
    try GLFW._KeyCallbackWrapper(window, key, Cint(0), action, Cint(0)) catch end
  end
  settle_window()
  # A folder dropped on the window
  paths = [drop]
  GC.@preserve paths begin
    pointers = [Base.unsafe_convert(Cstring, p) for p in paths]
    GLFW._DropCallbackWrapper(window, Cint(length(paths)), pointer(pointers))
  end
  settle_window()
  # Smaller windows, too small for everything to fit, somewhere else, and back again
  GLFW.SetWindowSize(window, 900, 600); settle_window()
  GLFW.SetWindowSize(window, 500, 320); settle_window()
  GLFW.SetWindowPos(window, 120, 120); settle_window()
  GLFW.SetWindowSize(window, 1100, 720); settle_window()
end

"""
Calls that only happen while code loads: compiling, expanding macros, working
with Julia's syntax, and Kip finding files. Kip's __init__ runs each time the
app starts, so it stays.
"""
const loading_only = r"Compiler\.|\bExpr\b|LineNumberNode|QuoteNode|GlobalRef|MacroTools|JuliaSyntax|LibGit2|\bPkg\.|Base\.Docs|Base\.Meta|Base\.include|Base\._?require|\bKip\.(?!__init__)"

"""
The type of the call on `line`, a `precompile(...)` line that `--record` wrote.
Julia writes a struct used as a type parameter by its field names, like
`Magnitude(value=Int8(0))`. Most structs have no constructor that takes those
names, so the struct is put back together from its fields instead.
"""
recorded_type(line) = begin
  rebuild(x) = x
  rebuild(x::Expr) = begin
    args = map(rebuild, x.args)
    fields = args[2:end]
    if x.head == :call && !isempty(fields) && all(a -> Meta.isexpr(a, :kw), fields)
      Expr(:new, args[1], (a.args[2] for a in fields)...)
    else
      Expr(x.head, args...)
    end
  end
  Core.eval(Main, rebuild(Meta.parse(line).args[2]))
end

"""
Mark the call `T` as one a trimmed app keeps, both as the method Julia would
compile for it and as the exact call. Dispatch can ask for either while the app
runs. False when there's no method for it.
"""
keep(T) = begin
  found = Base.Compiler.add_entrypoint(T)
  match = try Base._which(T) catch; nothing end
  match === nothing && return found
  push!(Base.Compiler._entrypoint_mis, Base.Compiler.specialize_method(match))
  true
end

"""
`T` with its trailing `Vararg` written out as 0 to 3 arguments of that type.
Julia records some calls to methods that take any number of arguments that way,
like `joinpath(String, String, Vararg{String})`, and can't always find the
method for the `Vararg` form.
"""
fixed_arity(T) = begin
  (T isa DataType && !isempty(T.parameters) && Base.isvarargtype(last(T.parameters))) || return Type[]
  head, rest = T.parameters[1:end-1], Base.unwrapva(last(T.parameters))
  [Tuple{head..., ntuple(_ -> rest, n)...} for n in 0:3]
end

"""
Where the code says `invokelatest`, a trimmed app calls `Base.invokelatest_trimmed`
with the same arguments. The recording can't tell which calls those are, so each
recorded call is also kept as a call through it.

JuliaC only defines `invokelatest_trimmed` after app.jl has run. Its build script
then marks `Base.task_done_hook` as an entry point, so this method of `entrypoint`
for that one call marks the calls through `invokelatest_trimmed` too. It relies on
the order of JuliaC's build script (juliac-buildscript.jl in JuliaC 0.3).
"""
const through_invokelatest = Type[]

Base.Experimental.entrypoint(f::typeof(Base.task_done_hook), argtypes::Tuple{DataType}) = begin
  Base.Compiler.add_entrypoint(Tuple{typeof(f), argtypes...})
  if isdefined(Base, :invokelatest_trimmed)
    # It takes keywords, so it also has a body function that the call goes through
    trimmed = Base.invokelatest_trimmed
    body = Base.bodyfunction(only(methods(trimmed)))
    no_keywords = typeof(pairs(NamedTuple()))
    for T in through_invokelatest
      keep(Tuple{typeof(trimmed), T.parameters...})
      keep(Tuple{typeof(body), no_keywords, typeof(trimmed), T.parameters...})
    end
    println(stderr, "Kept $(length(through_invokelatest)) calls through invokelatest_trimmed.")
    flush(stderr)
  end
  nothing
end

"Give each of Kip's modules and each loaded package a name in Main, as `--record` wrote them"
name_modules() = begin
  modules = [[nameof(m) => m for m in values(Kip.modules)]; [Symbol(id.name) => m for (id, m) in Base.loaded_modules]]
  for (name, m) in modules
    isdefinedglobal(Main, name) && getglobal(Main, name) === m && continue
    try
      Core.eval(Main, :(const $name = $m))
    catch e
      println(stderr, "Couldn't name $m in Main: ", sprint(showerror, e))
    end
  end
end

"""
While a trimmed app is built, mark each call in `file` as one the app keeps.
`file` is what `--record` wrote. Its lines name modules as Main sees them, so
Kip's modules and each loaded package get a name in Main first.
"""
keep_recorded(file) = begin
  name_modules()
  kept, missed = 0, String[]
  for line in eachline(file)
    (startswith(line, "precompile(") && !occursin(loading_only, line)) || continue
    T = try recorded_type(line) catch; nothing end
    # Both, since dispatch can ask for the Vararg form or an exact call
    if T !== nothing && (keep(T) | any(map(keep, fixed_arity(T))))
      kept += 1
      T isa DataType && push!(through_invokelatest, T)
    else
      push!(missed, line)
    end
  end
  println(stderr, "Kept $kept recorded calls. Couldn't find the methods for $(length(missed)).")
  foreach(l -> println(stderr, "  ", first(l, 300)), first(missed, 10))
  flush(stderr)
end

"""
The method instance that a dynamic call with argument types `T` compiles, for
the most specific method that matches, or `nothing`. It's what the compiler's
`compileable_specialization_for_call` gives, except that it doesn't give up
when a less specific method matches too, or when an argument type is abstract.
"""
compileable_method(T) = begin
  C = Base.Compiler
  match = Base._which(T; raise=false)
  match isa Core.MethodMatch || return nothing
  m = match.method
  sig = C.get_compileable_sig(m, match.spec_types, match.sparams)
  # While a trimmed app is built, that gives nothing when an argument's type is
  # abstract, like `Function`. Then do what dispatch does in the app: a function
  # argument that the method passes on without calling, and declares with an abstract
  # type, only counts as a `Function`.
  if sig === nothing
    declared = Base.unwrap_unionall(m.sig).parameters
    passed_on(i, t) = i > 1 && i <= length(declared) && !isconcretetype(declared[i]) && t !== Union{} &&
                      t <: Function && iszero(m.called >> (i - 2) & 1)
    sig = Tuple{(passed_on(i, t) ? Function : t for (i, t) in enumerate(match.spec_types.parameters))...}
    sig === match.spec_types && return nothing
  end
  sparams = sig === match.spec_types ? match.sparams :
    (ccall(:jl_type_intersection_with_env, Any, (Any, Any), sig, m.sig)::Core.SimpleVector)[2]::Core.SimpleVector
  C.specialize_method(m, sig, sparams)
end

# Julia 1.12 and 1.13 leave the methods that code reaches through `@invoke` out of
# a trimmed app. The compiler infers them, but doesn't add them to the code it
# compiles, so the app fails when it gets there. Base uses `@invoke`, e.g. in
# `repeat(::String, ::Int)`.
#
# JuliaC runs this trim check on that code just before it's compiled. While a
# trimmed app is built, it's replaced with one that compiles each method that an
# `@invoke` reaches and isn't there yet, until none are missing. It also compiles
# the one method a dynamic call can reach when its argument types only match one,
# like a function that's passed on without being called, typed only `Function`,
# or a call that splats tuples of known types into another function. It doesn't print
# the usual check's warnings, as listing those can take many minutes. It relies on
# the compiler's internals in Julia 1.13, and only runs with `APP_TRIM=safe` or
# `unsafe-warn`.
if trimming
  function Base.Compiler.verify_typeinf_trim(io::IO, codeinfos::Vector{Any}, onlywarn::Bool)
    C = Base.Compiler
    params = C.InferenceParams(; force_enable_inference=true)
    interp = C.NativeInterpreter(Base.get_world_counter(); inf_params=params)
    tried = Set{Core.MethodInstance}()
    failed = 0
    while true
      compiled = Core.CodeInstance[x for x in codeinfos if x isa Core.CodeInstance]
      # The code for an @invoke can be for the method with another argument signature.
      # What's missing is the method's own code, which the app calls instead.
      have = Set{Core.MethodInstance}(ci.def for ci in compiled if ci.def isa Core.MethodInstance)
      seen = Set{Any}(compiled)
      missing = Set{Core.MethodInstance}()
      for (i, x) in enumerate(codeinfos)
        x isa Core.CodeInstance || continue
        src = codeinfos[i + 1]::Core.CodeInfo
        sptypes = C.sptypes_from_meth_instance(C.get_ci_mi(x))
        for stmt in src.code
          Meta.isexpr(stmt, :(=)) && (stmt = stmt.args[2])
          if Meta.isexpr(stmt, :invoke)
            # An @invoke names the method itself, which the compiler doesn't follow
            edge = stmt.args[1]
            mi = edge isa Core.CodeInstance ? C.get_ci_mi(edge) : edge isa Core.MethodInstance ? edge : continue
            edge in seen && continue
          elseif Meta.isexpr(stmt, :call)
            # A dynamic call whose argument types only match one method, such as a
            # function passed on without being called, which is only typed `Function`
            argtypes = try
              Any[C.widenconst(C.argextype(a, src, sptypes)) for a in stmt.args]
            catch
              continue
            end
            if argtypes[1] === typeof(Core._apply_iterate)
              # f(args...): a call to f with the types of each splatted tuple's elements
              length(argtypes) >= 3 || continue
              splats = argtypes[4:end]
              all(t -> t <: Tuple && !Base.isvatuple(t) && t isa DataType, splats) || continue
              argtypes = Any[argtypes[3]; (p for t in splats for p in t.parameters)...]
            end
            argtypes[1] <: Core.Builtin && continue
            mi = compileable_method(Tuple{argtypes...})
            mi isa Core.MethodInstance || continue
          else
            continue
          end
          mi in have || mi in tried || push!(missing, mi)
        end
      end
      isempty(missing) && break
      union!(tried, missing)
      # One at a time, so a method the compiler fails on only leaves out itself
      done = Set{Core.CodeInstance}(compiled)
      for mi in missing
        queue = C.CompilationQueue(; interp)
        foreach(ci -> C.markinspected!(queue, ci), done)
        push!(queue, mi)
        try
          C.compile!(codeinfos, queue; invokelatest_queue=nothing, external_linkage=false)
        catch
          failed += 1
        end
        foreach(x -> x isa Core.CodeInstance && push!(done, x), codeinfos)
      end
    end
    println(io, "Compiled $(length(tried) - failed) more methods, reached through @invoke or dynamic calls. ",
            "The compiler failed on $failed.")
    nothing
  end
end
