# What each example's app.jl needs to be built into a standalone app. It goes at
# the top of app.jl, before anything else:
#
#     include("../mac_app/start.jl")
#
# The code at the top level of app.jl runs once, while the app is being built.
# It loads UI.jl and the example, and draws the example off screen so that code
# is compiled ahead of time. `main` runs each time the app opens, and calls
# `run_app`.

using Kip
# The packages that wrap native libraries, loaded before UI.jl needs them
import GLFW, Skia, Fontconfig, ModernGL, Libdl

# While Julia builds an app, packages don't run their __init__ as they load.
# Julia saves those to run when the app starts. But building the app runs the
# code in app.jl, which needs them now: Kip to find UI.jl's files, the libraries
# that GLFW and Skia wrap, and so on. Running them here is harmless, since they
# run again when the app starts.
const building = ccall(:jl_generating_output, Cint, ()) == 1
const started = Set{Module}()
const stdlibs = Set(readdir(Sys.STDLIB))
"""
Run the __init__ of each package loaded so far that hasn't run it yet. Julia's
own standard libraries are left alone: they set up things like the maths
libraries, which don't take kindly to starting twice. app.jl calls this again
after it loads the example, for the packages the example loaded.
"""
start_packages() = begin
  waiting = filter(collect(values(Base.loaded_modules))) do m
    # Kip runs the __init__ of each UI.jl file itself, as it includes it
    !(m in started || m in (Core, Base, Main) || string(nameof(m)) in stdlibs ||
      Base.PkgId(m) in Base._sysimage_modules || m in values(Kip.modules)) && isdefined(m, :__init__)
  end
  # There's no record of the order they loaded in, so one that needs another
  # library loaded first just tries again after the rest
  problems = Dict{Module,Any}()
  for _ in 1:4
    failed = Module[]
    for m in waiting
      try
        # GLFW's __init__ also asks to shut GLFW down when Julia exits, which
        # Julia refuses while it builds an app. Starting GLFW is all that's needed.
        m === GLFW ? GLFW.Init() : Base.invokelatest(getfield(m, :__init__))
        push!(started, m)
      catch e
        problems[m] = e
        push!(failed, m)
      end
    end
    waiting = failed
    isempty(waiting) && break
  end
  println(stderr, "Started: ", join(sort(string.(nameof.(collect(started)))), " "))
  isempty(waiting) || error("These packages couldn't start: ",
                            join(("$m ($(sprint(showerror, problems[m])))" for m in waiting), ", "))
end
building && (Kip.__init__(); start_packages())

"""
While the app was built, each package that wraps a library found that library
in ~/.julia and remembered where. Make them forget, so that when the app starts
they look again and find the copies inside it. Skia.jl keeps its path in a
constant, so that becomes the library's own name, which finds whichever copy
Skia_jll loaded. Skia's calls were compiled with the old path, so app.jl draws
the example again after this.
"""
relocate!() = begin
  for m in values(Base.loaded_modules)
    name = string(nameof(m))
    (endswith(name, "_jll") && !(name in stdlibs)) || continue
    for g in names(m, all=true)
      endswith(string(g), "_path") && isdefined(m, g) && getglobal(m, g) isa String || continue
      try setglobal!(m, g, nothing) catch end
    end
  end
  Core.eval(Skia, :(const libskia = "@rpath/libskia.dylib"))
end

"""
Run the __init__ of each of UI.jl's files. Kip included them while the app was
built, so Julia doesn't know to run them when the app starts.
"""
start_ui() = begin
  n = 0
  for path in Kip.fallback_paths
    m = Kip.modules[path]
    isdefined(m, :__init__) || continue
    Base.invokelatest(getfield(m, :__init__))
    n += 1
  end
  n
end

"""
Start the app and call `open_app(args)`, which shows its window. With
`--self-test` in `args` it runs `warm_up` instead, to check that the code it
compiled while the app was built is all still there. `--libraries` then lists
the native libraries the app loaded, so the build can leave out the rest.
"""
run_app(open_app, args, warm_up) = begin
  n = start_ui()
  if "--self-test" in args
    t = try
      @elapsed warm_up()
    catch e
      println(stderr, "Self-test failed: ", sprint(showerror, e, catch_backtrace()))
      return 1
    end
    workers = Threads.nthreads(:default)
    println("Self-test passed in ", round(t, digits=2), " s. It started $n of UI.jl's files, ",
            "with $workers worker thread", workers == 1 ? "." : "s.")
    "--libraries" in args && foreach(println, Libdl.dllist())
    return 0
  end
  open_app(args)
  0
end
