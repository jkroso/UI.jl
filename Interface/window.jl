# Window chrome on macOS: hiding the title bar, moving the window by dragging
# the app's own top bar instead, and dark mode. None of it does anything on
# other systems.

@use GLFW
@use "github.com/jkroso/MiniFB.jl" AbstractWindow Keys
@use "./objc" cls msg send get_value nsstring jstring with_pool

nswindow(w::AbstractWindow) = ccall((:glfwGetCocoaWindow, GLFW.libglfw), Ptr{Cvoid}, (GLFW.Window,), w.glfw[1])

const full_size_content = UInt(1) << 15 # NSWindowStyleMaskFullSizeContentView
const title_hidden = 1                   # NSWindowTitleHidden

"""
Hide the window's title bar, the way Finder does. The app's content then runs
up to the top edge of the window, and the close, minimise and zoom buttons
float over its top left corner, so leave about 70px × 40px clear there. Without
a title bar the window can only be moved by dragging somewhere that calls
`drag_window!`. Call it once the window is open, e.g. from `onopen`.
"""
hide_titlebar!(w::AbstractWindow) = begin
  (Sys.isapple() && !isempty(w.glfw)) || return w
  win = nswindow(w)
  with_pool() do
    send(win, "setStyleMask:", get_value(UInt, win, "styleMask") | full_size_content)
    send(win, "setTitlebarAppearsTransparent:", true)
    send(win, "setTitleVisibility:", title_hidden)
  end
  w
end

"""
Move the window with the mouse, starting from the press that's happening now.
Call it from a `KeyPress{Keys.mouse_left}` handler on an empty part of your top
bar. It returns when the mouse button is released.
"""
drag_window!(w::AbstractWindow) = begin
  (Sys.isapple() && !isempty(w.glfw)) || return w
  win = nswindow(w)
  with_pool() do
    event = msg(msg(cls("NSApplication"), "sharedApplication"), "currentEvent")
    event == C_NULL || msg(win, "performWindowDragWithEvent:", event)
  end
  # The drag uses up the release, so the window never hears the button go up
  Keys.mouse_left in w.keys && (w.keys ⊻= Keys.mouse_left)
  w
end

"True when macOS is in dark mode. It follows the setting as it changes."
dark_mode() = Sys.isapple() && with_pool() do
  app = msg(cls("NSApplication"), "sharedApplication")
  occursin("Dark", jstring(msg(msg(app, "effectiveAppearance"), "name")))
end

"""
Draw the parts of the window that macOS draws, like the close button and the
window's edge, in dark or light mode. Your app draws everything else, so it
picks its own colours to match.
"""
set_dark!(w::AbstractWindow, dark::Bool) = begin
  (Sys.isapple() && !isempty(w.glfw)) || return w
  with_pool() do
    name = nsstring(dark ? "NSAppearanceNameDarkAqua" : "NSAppearanceNameAqua")
    msg(nswindow(w), "setAppearance:", msg(cls("NSAppearance"), "appearanceNamed:", name))
  end
  w
end

export hide_titlebar!, drag_window!, dark_mode, set_dark!
