# The entry point for a standalone build of the Finder example. build.jl
# compiles it with JuliaC into an app that runs without Julia installed.
#
# The code at the top level runs once, while the app is being built. It loads
# UI.jl and the example, reads the icons the app uses, and draws each view off
# screen so that code is compiled ahead of time. `main` runs each time the app
# opens.

include("../mac_app/start.jl")

@use "../26_finder" build_finder open_finder colours select_only! item! Heading TOOLBAR_H HEADER_H _listings _entries
@use "../27_disk_usage" busy
@use "github.com/jkroso/MiniFB.jl" Window KeyPress KeyRelease MouseMove Keys onkey onmouse
@use "github.com/jkroso/Font.jl/units" px
@use "../../Interface/Geometric" Box width height background
@use "../../Interface/abstract" describe focus
@use "../../Interface/Semantic/Icon" load_icon
@use "../../Interface/draw" frame draw
@use "../../Interface/save" save_png
@use GeometryBasics: Vec2

building && start_packages()

# Icons are read from UI.jl's Icons folder the first time they're drawn. Reading
# them now keeps them in the app, so it doesn't need that folder.
foreach(load_icon, ["app", "arrow-down-circle", "bullseye", "chevron-down", "chevron-left", "chevron-right",
                    "chevron-up", "cloud", "display", "file-earmark", "file-earmark-fill", "folder-fill", "grid",
                    "hdd", "house", "layout-three-columns", "list-ul", "search", "three-dots", "trash3",
                    "x-circle-fill"])

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
  # The menu a right-click opens, in each view. Hover a choice and close it with
  # esc, then duplicate a file from it and Quick Look the copy.
  right_click(x, y) = begin
    mouse(x, y); hold((Keys.mouse_right,))
    onkey(w, KeyPress{Keys.mouse_right}(0, w)); frame(w)
    release((Keys.mouse_right,))
    onkey(w, KeyRelease{Keys.mouse_right}(0, w)); frame(w)
  end
  for (mode, x, y) in ((:list, 400, row(1)), (:icons, 400, TOOLBAR_H.value + 60), (:columns, 300, TOOLBAR_H.value + 15))
    f.mode = mode; frame(w)
    right_click(x, y); mouse(x + 30, y + 30); frame(w); press(Keys.escape)
  end
  f.mode = :list; frame(w)
  right_click(400, row(1)); click(f.menu.children[3])
  right_click(400, row(1)); click(f.menu.children[2]); press(Keys.escape)
  # The sunburst view in each appearance, once its scan of the folder is done.
  # Leaving it with ⌘2 keeps the finished scan for next time.
  for appearance in (:light, :dark)
    f.appearance = appearance
    press(Keys.var"4", Keys.cmd)
    stop = time() + 30
    while busy(f.usage) && time() < stop
      frame(w)
    end
    mouse(560, 300); frame(w); mouse(560, 200); frame(w)
    press(Keys.var"2", Keys.cmd)
  end
  rm(dir, recursive=true)
end

warm_up()

if building
  relocate!()
  # Skia's calls were compiled with the old path, so compile them again
  warm_up()
end

function (@main)(args::Vector{String})
  # Forget the folders the warm up read. They were on the machine that built the app.
  empty!(_listings)
  empty!(_entries)
  run_app(open_finder, args, warm_up)
end
