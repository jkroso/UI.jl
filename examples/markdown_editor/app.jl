# The entry point for a standalone build of the Markdown editor example.
# build.jl compiles it with JuliaC into an app.
#
# The code at the top level runs once, while the app is being built. It loads
# UI.jl and the example, reads the icons the app uses, and types into a document
# off screen so that code is compiled ahead of time. `main` runs each time the
# app opens.
#
# With no file to open, the app shows the welcome page that is in UI.jl's own
# folder, so that page's live blocks only work on the Mac the app was built on.

include("../mac_app/start.jl")

@use "../28_markdown_editor" build_editor open_editor WELCOME restyle!
@use "github.com/jkroso/MiniFB.jl" Window KeyPress KeyRelease MouseMove Keys onkey onmouse
@use "github.com/jkroso/Font.jl/units" px
@use "../../Interface/abstract" focus
@use "../../Interface/Semantic/Icon" load_icon
@use "../../Interface/draw" frame
@use GeometryBasics: Vec2
# What the live blocks of the example pages load. A file that's loaded now is
# in the app. The app can't load a file that it hasn't seen.
@use "../../Interface/Semantic" => Semantic
@use "../../Interface/Semantic/ListTree" => ListTree
@use "./widgets" => widgets

building && start_packages()

# Icons are read from UI.jl's Icons folder the first time they're drawn. Reading
# them now keeps them in the app, so it doesn't need that folder.
foreach(load_icon, ["chevron-right", "circle-half", "file-earmark", "file-earmark-text", "folder", "fonts",
                    "layout-sidebar", "list-nested", "search", "text-center", "text-left", "text-right"])

# The welcome page's text, to type into while the app warms up
const page = read(WELCOME, String)

"""
Open a copy of the welcome page in a throwaway folder and send input to a
window that isn't on screen. While the app is built this compiles the code it
runs. `--self-test` runs it again inside the finished app, to check that code
is all still there.
"""
warm_up() = begin
  dir = mktempdir()
  write(joinpath(dir, "welcome.md"), page)
  write(joinpath(dir, "notes.md"), "# Notes\n\nSome text.\n")
  e = build_editor(joinpath(dir, "welcome.md"))
  w = Window(e, title="warm up", size=(1100px, 800px))
  focus(e)
  hold(keys) = foreach(k -> (w.keys |= k), keys)
  release(keys) = foreach(k -> (w.keys ⊻= k), keys)
  press(k, mods...) = (hold(mods); onkey(w, KeyPress{k}(0, w)); onkey(w, KeyRelease{k}(0, w)); release(mods); frame(w))
  mouse(x, y) = (pos = Vec2{px}(px(x), px(y)); onmouse(w, MouseMove(pos, w)); w.mouse = pos; frame(w))
  click(x, y) = begin
    mouse(x, y)
    hold((Keys.mouse_left,)); onkey(w, KeyPress{Keys.mouse_left}(0, w))
    release((Keys.mouse_left,)); onkey(w, KeyRelease{Keys.mouse_left}(0, w))
    frame(w)
  end
  frame(w)
  # Each set of colours and each font
  for theme in (:paper, :night, :sepia), serif in (false, true)
    e.theme, e.serif = theme, serif
    restyle!(e)
    frame(w)
  end
  # Down the whole page a line at a time: through the table, the code, the live blocks and the sheet
  for _ in 1:length(e.buf.lines)
    press(Keys.down)
    # Type, go to the next cell and back, select and undo, in whatever the caret is in
    press(Keys.a); press(Keys.backspace)
    press(Keys.tab); press(Keys.tab, Keys.shft)
    press(Keys.right, Keys.shft); press(Keys.left)
    press(Keys.z, Keys.cmd); press(Keys.z, Keys.cmd); press(Keys.z, Keys.cmd)
  end
  # A new line at the end, a list and a new sheet
  press(Keys.down, Keys.cmd); press(Keys.enter)
  foreach(press, (Keys.minus, Keys.space, Keys.a, Keys.enter, Keys.enter))
  foreach(press, (Keys.tilde, Keys.tilde, Keys.tilde, Keys.s, Keys.h, Keys.e, Keys.e, Keys.t, Keys.enter))
  foreach(press, (Keys.a, Keys.tab, Keys.var"2", Keys.enter, Keys.b, Keys.tab, Keys.a, Keys.enter, Keys.enter))
  # Select everything, copy nothing, make it bold and undo
  press(Keys.a, Keys.cmd); press(Keys.b, Keys.cmd); press(Keys.z, Keys.cmd); press(Keys.escape)
  # Bigger and smaller text, the sidebar, the outline and the file finder
  press(Keys.equal, Keys.cmd); press(Keys.minus, Keys.cmd); press(Keys.var"0", Keys.cmd)
  press(Keys.backslash, Keys.cmd); press(Keys.backslash, Keys.cmd)
  press(Keys.p, Keys.cmd); press(Keys.n); press(Keys.escape)
  # The mouse over the top bar's buttons, and a click and a drag on the page
  foreach(x -> mouse(x, 22), (50, 550, 940, 1000, 1040, 1075))
  press(Keys.up, Keys.cmd)
  click(400, 200); click(400, 200); click(500, 400)
  # The layout inspector
  press(Keys.i, Keys.cmd, Keys.opt); press(Keys.i, Keys.cmd, Keys.opt)
  rm(dir, recursive=true)
end

warm_up()

if building
  relocate!()
  # Skia's calls were compiled with the old path, so compile them again
  warm_up()
end

function (@main)(args::Vector{String})
  run_app(open_editor, args, warm_up)
end
