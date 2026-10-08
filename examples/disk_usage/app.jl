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
@use "../../Interface/draw" frame
@use GeometryBasics: Vec2

building && start_packages()

# Icons are read from UI.jl's Icons folder the first time they're drawn. Reading
# them now keeps them in the app, so it doesn't need that folder.
foreach(load_icon, ["chevron-right", "file-earmark-fill", "folder-fill", "three-dots"])

"""
A throwaway folder to scan. It has folders deeper than the chart's rings, one
with more files than the list shows, an empty one and one that can't be read.
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
  chmod(joinpath(dir, "locked"), 0o000)
  dir
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
    end
    # Into a folder with more files than the list shows. Scroll its list.
    zoom!(a, child(a.scan.root, "many")); settle()
    mouse(cx * 2 + 100, 300)
    foreach(_ -> (onscroll(w, Vec2{px}(0px, -5px)); frame(w)), 1:4)
    foreach(y -> mouse(cx * 2 + 100, y), 100:26:400)
    press(Keys.escape); settle()
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

function (@main)(args::Vector{String})
  run_app(open_disk_usage, args, warm_up)
end
