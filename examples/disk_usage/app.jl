# The entry point for a standalone build of the Disk Usage example. build.jl
# compiles it with JuliaC into an app that runs without Julia installed.
#
# The code at the top level runs once, while the app is being built. It loads
# UI.jl and the example, reads the icons the app uses, and scans a folder of
# made-up files off screen so that code is compiled ahead of time. `main` runs
# each time the app opens.

include("../mac_app/start.jl")

@use "../27_disk_usage" DiskUsage open_disk_usage scan! zoom! LIST_W
@use "./scan" Item Scan running stop!
@use "github.com/jkroso/MiniFB.jl" Window KeyPress KeyRelease MouseMove Keys onkey onmouse onscroll onfiledrop
@use "github.com/jkroso/Font.jl/units" px
@use "../../Interface/abstract" focus
@use "../../Interface/Semantic/Icon" load_icon
@use "../../Interface/draw" frame _scenes semantic_source
@use "../../Interface/Specific" ConcreteRect
@use GeometryBasics: Vec2

building && start_packages()

# Icons are read from UI.jl's Icons folder the first time they're drawn. Reading
# them now keeps them in the app, so it doesn't need that folder.
foreach(load_icon, ["chevron-right", "file-earmark-fill", "folder-fill", "three-dots"])

"""
A throwaway folder to scan. It has folders deeper than the chart's rings, one
with more files than the list shows, an empty one, one that can't be read, and
names too long to fit or in other scripts, as a real disk has.
"""
test_folder() = begin
  dir = mktempdir()
  write(joinpath(dir, "big.bin"), zeros(UInt8, 1_000_000))
  for (folder, files) in ("documents" => 3, "documents/old" => 2, "photos" => 6, "many" => 250,
                          "deep/a/b/c/d/e/f" => 1, "empty" => 0, "locked" => 1)
    mkpath(joinpath(dir, folder))
    for i in 1:files
      write(joinpath(dir, folder, "file $i.txt"), "x"^(100i))
    end
  end
  long = "a folder with a name that is far too long to fit in the list or in the path at the top"
  mkpath(joinpath(dir, long, long))
  write(joinpath(dir, long, "a file with a very long name that has to be shortened in the middle.txt"), "x"^5000)
  write(joinpath(dir, long, long, "inside.txt"), "x"^3000)
  for name in ("写真とビデオ.txt", "Screenshot 2026-10-08 at 10.00.00\u202fam.png", "😀 emoji.txt", "Ünïcödé.txt")
    write(joinpath(dir, name), "x"^300)
  end
  chmod(joinpath(dir, "locked"), 0o000)
  dir
end

"""
A point on one thing of each kind in window `w`, as its last frame laid them out.
A kind is the kind of layout node, of what it draws and of the thing it shows. A
grid of points can miss small things, like the icon in a row.
"""
kinds(w) = begin
  points = Dict{Any,Tuple{Float64,Float64}}()
  visit(n) = begin
    shows = applicable(semantic_source, n) ? semantic_source(n) : nothing
    if n.width > 0px && n.height > 0px
      get!(points, (typeof(n), typeof(n.from), typeof(shows)), (n.left.value + n.width.value / 2, n.top.value + n.height.value / 2))
    end
    n isa ConcreteRect && foreach(visit, n.children)
  end
  visit(_scenes[objectid(w)])
  collect(values(points))
end

"The item called `name` in `folder`"
child(folder::Item, name) = first(c for c in folder.children if c.name == name)

"""
Scan a folder and send input to a window that isn't on screen. While the app is
built this compiles the code it runs. `--self-test` runs it again inside the
finished app, to check that code is all still there. It only reads the folder
it makes, and none of its menus run an action.
"""
warm_up() = begin
  dir = test_folder()
  a = DiskUsage(Scan(dir))
  w = Window(a, title="warm up", size=(1100px, 720px))
  focus(a)
  try
    hold(keys) = foreach(k -> (w.keys |= k), keys)
    release(keys) = foreach(k -> (w.keys ⊻= k), keys)
    press(k, mods...) = (hold(mods); onkey(w, KeyPress{k}(0, w)); onkey(w, KeyRelease{k}(0, w)); release(mods); frame(w))
    mouse(x, y) = (pos = Vec2{px}(px(x), px(y)); onmouse(w, MouseMove(pos, w)); w.mouse = pos; frame(w))
    click(x, y, button=Keys.mouse_left) = begin
      mouse(x, y)
      hold((button,)); onkey(w, KeyPress{button}(0, w))
      release((button,)); onkey(w, KeyRelease{button}(0, w))
      frame(w)
    end
    tap(node, button=Keys.mouse_left) = (onkey(node, KeyPress{button}(0, w)); onkey(w, KeyRelease{button}(0, w)); frame(w))
    # Draw frames until the scan has finished and the chart has stopped moving
    settle() = begin
      stop = time() + 60
      while running(a.scan) || a.moving !== nothing
        time() < stop || error("The scan of $dir didn't finish")
        frame(w)
      end
      frame(w)
    end
    # Where the chart is: in the middle of the space left of the list, below the toolbar
    cx, cy = (1100 - LIST_W.value) / 2, 32 + (720 - 32) / 2
    radius = min(1100 - LIST_W.value - 48, 720 - 32 - 48) / 2
    at(r, θ) = (cx + r * radius * cosd(θ), cy + r * radius * sind(θ))
    for appearance in (:system, :light, :dark)
      a.appearance = appearance
      scan!(a, dir)
      settle()
      # Hover the middle and each ring, then the toolbar and the list
      for r in (0.1, 0.4, 0.6, 0.85), θ in 0:30:330
        mouse(at(r, θ)...)
      end
      foreach(x -> mouse(x, 16), (20, 96, 300, 1050))
      foreach(y -> mouse(cx * 2 + 100, y), 40:26:400)
      foreach(p -> mouse(p...), kinds(w))
    end
    # Click and right-click one thing of each kind. Then go back to the top, and click
    # away from any menu to close it without choosing anything.
    for p in kinds(w)
      click(p...); click(p..., Keys.mouse_right); click(5, 5)
      # Without waiting for the zoom to play out, which the rest of the warm up does
      zoom!(a, a.scan.root); a.moving = nothing; settle()
    end
    # Into a folder with more files than the list shows. Scroll its list.
    zoom!(a, child(a.scan.root, "many")); settle()
    mouse(cx * 2 + 100, 300)
    foreach(_ -> (onscroll(w, Vec2{px}(0px, -5px)); frame(w)), 1:4)
    foreach(y -> mouse(cx * 2 + 100, y), 100:26:400)
    press(Keys.escape); settle()
    # A folder with a name too long for the path at the top, then back out
    long = only(c for c in a.scan.root.children if startswith(c.name, "a folder with"))
    zoom!(a, only(c for c in long.children if c.folder)); settle()
    press(Keys.escape); settle(); press(Keys.escape); settle()
    # Deep enough that the rings run out, then back by the path at the top
    deep = child(a.scan.root, "deep")
    zoom!(a, child(child(deep, "a"), "b")); settle()
    tap(a.crumbs[deep]); settle()
    tap(a.crumbs[a.scan.root]); settle()
    # The empty folder and the one that can't be read
    for name in ("empty", "locked")
      zoom!(a, child(a.scan.root, name)); settle()
      press(Keys.up, Keys.cmd); settle()
    end
    # Click slices on the first ring to zoom in, and the middle to zoom out
    for θ in 0:60:300
      click(at(0.35, θ)...); settle()
      click(cx, cy); settle()
    end
    # Right-click a slice and some rows for their menus. Click away to close each one.
    for target in (at(0.35, 0), (cx * 2 + 100, 110), (cx * 2 + 100, 136))
      click(target..., Keys.mouse_right)
      mouse(target[1] + 20, target[2] + 16)
      click(20, 700)
    end
    # Scan again with ⌘R, open and close the layout inspector, and drag the window by
    # its toolbar and by the top of the list
    press(Keys.r, Keys.cmd); settle()
    press(Keys.i, Keys.cmd, Keys.opt); press(Keys.i, Keys.cmd, Keys.opt)
    click(600, 16); click(cx * 2 + 100, 16)
    # Drop a folder on the window, then the whole test folder again
    onfiledrop(w, [joinpath(dir, "documents")]); settle()
    onfiledrop(w, [dir]); settle()
  finally
    stop!(a.scan)
    chmod(joinpath(dir, "locked"), 0o755)
    rm(dir, recursive=true)
  end
end

warm_up()

if building
  relocate!()
  # Skia's calls were compiled with the old path, so compile them again
  warm_up()
  # Let the scan's worker threads see that it's over and stop, before Julia saves the app
  sleep(0.5)
end

"""
Choose each item in a folder's menu and in a file's menu, in a window that isn't
on screen. The warm up doesn't, since Show in Finder and Open run `open`. When
`record` runs, `open` does nothing.
"""
use_menus() = begin
  dir = test_folder()
  a = DiskUsage(Scan(dir))
  w = Window(a, title="menus", size=(1100px, 720px))
  focus(a)
  try
    stop = time() + 60
    while running(a.scan)
      time() < stop || error("The scan of $dir didn't finish")
      frame(w)
    end
    frame(w)
    # Each menu opens where the pointer is, at the top left, with items 32 pixels tall
    for name in ("documents", "big.bin"), item in 1:2
      onkey(a.rows[child(a.scan.root, name)], KeyPress{Keys.mouse_right}(0, w)); frame(w)
      pos = Vec2{px}(20px, px(16 + 32 * (item - 1)))
      onmouse(w, MouseMove(pos, w)); w.mouse = pos
      onkey(w, KeyPress{Keys.mouse_left}(0, w)); onkey(w, KeyRelease{Keys.mouse_left}(0, w)); frame(w)
      w.mouse = Vec2{px}(0px, 0px)
    end
    while running(a.scan); frame(w) end
  finally
    stop!(a.scan)
    chmod(joinpath(dir, "locked"), 0o755)
    rm(dir, recursive=true)
  end
end

"""
Open the real window on a throwaway folder and send it every kind of input, then
the app's shortcuts. build.jl runs the app with `--record` before it builds a
trimmed app, so the calls this makes are kept. See ../mac_app/record.jl.
"""
record() = begin
  use_menus()
  dir = test_folder()
  try
    record_window(() -> open_disk_usage([dir])) do window
      sleep(1)  # time for the scan
      points = [(x, y) for y in 16:64:700 for x in 40:100:1080]
      send_every_input(window, points=points, drop=joinpath(dir, "documents"))
      press_keys(window, GLFW.KEY_R, GLFW.KEY_LEFT_SUPER)
      press_keys(window, GLFW.KEY_UP, GLFW.KEY_LEFT_SUPER)
      press_keys(window, GLFW.KEY_I, GLFW.KEY_LEFT_SUPER, GLFW.KEY_LEFT_ALT)
      press_keys(window, GLFW.KEY_I, GLFW.KEY_LEFT_SUPER, GLFW.KEY_LEFT_ALT)
      press_keys(window, GLFW.KEY_ESCAPE)
    end
  finally
    chmod(joinpath(dir, "locked"), 0o755)
    rm(dir, recursive=true)
  end
end

# A trimmed app keeps only the methods main calls, and the ones --record saw
trimming && keep_recorded(ENV["APP_CALLS"])

function (@main)(args::Vector{String})
  run_app(open_disk_usage, args, warm_up, record=record)
end
