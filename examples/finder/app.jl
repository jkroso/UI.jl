# The entry point for a standalone build of the Finder example. build.jl
# compiles it with JuliaC into an app that runs without Julia installed.
#
# The code at the top level runs once, while the app is being built. It loads
# UI.jl and the example, reads the icons the app uses, and draws each view off
# screen so that code is compiled ahead of time. `main` runs each time the app
# opens.

using Kip
# The packages that wrap native libraries, loaded before UI.jl needs them
import GLFW, Skia, Fontconfig, ModernGL

# While Julia builds an app, packages don't run their __init__ as they load.
# Julia saves those to run when the app starts. But building the app runs the
# code below, which needs them now: Kip to find UI.jl's files, the libraries
# that GLFW and Skia wrap, and so on. Running them here is harmless, since they
# run again when the app starts.
const building = ccall(:jl_generating_output, Cint, ()) == 1
const started = Set{Module}()
const stdlibs = Set(readdir(Sys.STDLIB))
"""
Run the __init__ of each package loaded so far that hasn't run it yet. Julia's
own standard libraries are left alone: they set up things like the maths
libraries, which don't take kindly to starting twice.
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

include(joinpath(@__DIR__, "..", "26_finder.jl"))
@use "../../Interface/Semantic/Icon" load_icon
@use "../../Interface/draw" frame
@use GeometryBasics: Vec2
@use Libdl

building && start_packages()

# Icons are read from UI.jl's Icons folder the first time they're drawn. Reading
# them now keeps them in the app, so it doesn't need that folder.
foreach(load_icon, ["app", "arrow-down-circle", "chevron-down", "chevron-left", "chevron-right", "chevron-up",
                    "cloud", "display", "file-earmark", "folder-fill", "grid", "hdd", "house",
                    "layout-three-columns", "list-ul", "search", "trash3", "x-circle-fill"])

"""
Show each view and send input to a window that isn't on screen, in a throwaway
folder. While the app is built this compiles the code it runs. `--self-test`
runs it again inside the finished app, to check that code is all still there.
"""
warm_up() = begin
  dir = mktempdir()
  for name in ("notes.txt", "todo.md", "data.csv")
    write(joinpath(dir, name), "Some text for Quick Look\n")
  end
  mkpath(joinpath(dir, "folder"))
  # A small picture, for the column view's preview and Quick Look
  save_png(joinpath(dir, "picture.png"), (40px, 30px)) do ctx, size
    draw(ctx, size, describe(Box(width(40px), height(30px), background(colours.accent)), size))
  end
  f = build_finder(dir)
  w = Window(f, title="warm up", size=(1100px, 680px))
  focus(f)
  hold(keys) = foreach(k -> (w.keys |= k), keys)
  release(keys) = foreach(k -> (w.keys ⊻= k), keys)
  press(k, mods...) = (hold(mods); onkey(w, KeyPress{k}(0, w)); onkey(w, KeyRelease{k}(0, w)); release(mods); frame(w))
  mouse(x, y) = (pos = Vec2{px}(px(x), px(y)); onmouse(w, MouseMove(pos, w)); w.mouse = pos)
  click(node) = (onkey(node, KeyPress{Keys.mouse_left}(0, w)); onkey(w, KeyRelease{Keys.mouse_left}(0, w)); frame(w))
  for appearance in (:light, :dark), mode in (:icons, :list, :columns)
    f.appearance, f.mode = appearance, mode
    frame(w)
    foreach(press, (Keys.down, Keys.down, Keys.right, Keys.left, Keys.up))
  end
  # Quick Look on a text file and on the picture, then the picture in the column view
  f.mode = :list
  frame(w)
  for name in ("notes.txt", "picture.png")
    select_only!(f, joinpath(dir, name)); frame(w)
    press(Keys.space); press(Keys.escape)
  end
  f.mode = :columns; f.trail = [joinpath(dir, "picture.png")]; frame(w)
  f.mode = :list; frame(w)
  # Sort by each column, show hidden files, type to select, and search
  for key in (:date, :size, :kind, :name)
    click(item!(f, ("heading", key), () -> Heading(key=key)))
  end
  press(Keys.period, Keys.cmd, Keys.shft); press(Keys.period, Keys.cmd, Keys.shft)
  press(Keys.n); press(Keys.o)
  press(Keys.f, Keys.cmd); press(Keys.t); press(Keys.o); press(Keys.backspace); press(Keys.escape)
  # Into a folder and out again, then back and forward
  select_only!(f, joinpath(dir, "folder")); frame(w)
  press(Keys.down, Keys.cmd); press(Keys.up, Keys.cmd)
  press(Keys.left_bracket, Keys.cmd); press(Keys.right_bracket, Keys.cmd)
  foreach(k -> press(k, Keys.cmd), (Keys.var"1", Keys.var"2", Keys.var"3", Keys.var"2"))
  # The layout inspector
  press(Keys.i, Keys.cmd, Keys.opt); press(Keys.i, Keys.cmd, Keys.opt)
  # Drag the first file onto the folder, then put it back
  row(i) = TOOLBAR_H.value + HEADER_H.value + 24 * (i - 1) + 12
  folder = findfirst(e -> e.folder, f.order)
  mouse(400, row(1)); hold((Keys.mouse_left,))
  onkey(w, KeyPress{Keys.mouse_left}(0, w)); frame(w)
  mouse(410, row(1) + 10); frame(w)
  mouse(400, row(folder)); frame(w)
  release((Keys.mouse_left,))
  onkey(w, KeyRelease{Keys.mouse_left}(0, w)); frame(w)
  press(Keys.z, Keys.cmd)
  # A selection box across empty space
  mouse(700, 600); hold((Keys.mouse_left,))
  onkey(w, KeyPress{Keys.mouse_left}(0, w)); frame(w)
  mouse(690, 590); mouse(650, row(1)); frame(w)
  release((Keys.mouse_left,))
  onkey(w, KeyRelease{Keys.mouse_left}(0, w)); frame(w)
  rm(dir, recursive=true)
end

warm_up()

"""
While the app was built, each package that wraps a library found that library
in ~/.julia and remembered where. Make them forget, so that when the app starts
they look again and find the copies inside it. Skia.jl keeps its path in a
constant, so that becomes the library's own name, which finds whichever copy
Skia_jll loaded.
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

if building
  relocate!()
  # Skia's calls were compiled with the old path, so compile them again
  warm_up()
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

function (@main)(args::Vector{String})
  n = start_ui()
  # Forget the folders the warm up read. They were on the machine that built the app.
  empty!(_listings)
  empty!(_entries)
  if "--self-test" in args
    t = try
      @elapsed warm_up()
    catch e
      println(stderr, "Self-test failed: ", sprint(showerror, e, catch_backtrace()))
      return 1
    end
    println("Self-test passed in ", round(t, digits=2), " s. It started $n of UI.jl's files.")
    # Which native libraries the app loaded, so unused ones can be left out
    "--libraries" in args && foreach(println, Libdl.dllist())
    return 0
  end
  open_finder(args)
  return 0
end
