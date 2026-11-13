# Window chrome on macOS: hiding the title bar, moving the window by dragging
# the app's own top bar instead, dark mode and the system's own menus. None of
# it does anything on other systems.

@use GLFW
@use "github.com/jkroso/MiniFB.jl" AbstractWindow Keys redraw
@use "./objc" libobjc cls sel msg send get_value nsstring jstring with_pool

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

# --- the system's menu ---------------------------------------------------------
#
# macOS draws this menu and runs it, so it looks and works like every other
# menu on the Mac: its shape, its highlight, the arrow keys and Return. macOS
# tells an object which item was chosen, so there's a small class for that.

struct NSPoint
  x::Float64
  y::Float64
end

const on_choice = Ref{Any}(nothing)           # what to call with the item that's chosen from the menu that's showing
const choices = Tuple[]                       # the place of each item of that menu. An item's tag is its place in this list.
const menu_target = Ref{Ptr{Cvoid}}(C_NULL)

"macOS calls this with the item that was chosen"
note_choice(self::Ptr{Cvoid}, cmd::Ptr{Cvoid}, item::Ptr{Cvoid})::Cvoid = begin
  try
    tag = get_value(Int, item, "tag")
    (on_choice[] === nothing || !(1 <= tag <= length(choices))) || Base.invokelatest(on_choice[], choices[tag]...)
  catch err
    # An error mustn't go back into macOS's own code
    @error "A menu's `onselect` failed" exception=(err, catch_backtrace())
  end
  nothing
end

"The object that each item of a menu tells when it's chosen"
target() = begin
  menu_target[] == C_NULL || return menu_target[]
  class = cls("UIMenuTarget")
  if class == C_NULL
    class = ccall((:objc_allocateClassPair, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Cstring, Csize_t), cls("NSObject"), "UIMenuTarget", 0)
    ccall((:objc_registerClassPair, libobjc), Cvoid, (Ptr{Cvoid},), class)
  end
  # The class outlives this file when the file is loaded again, so give it the function as it is now
  ccall((:class_replaceMethod, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Cstring), class, sel("choose:"),
        @cfunction(note_choice, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid})), "v@:@")
  menu_target[] = msg(msg(class, "alloc"), "init")
end

"""
Show a macOS menu of `items` in the window and wait until it closes. Each of
`items` is one of these:

- a title, like `"Copy"`
- `"-"`, which is a line between two groups of items
- `title => items`, which is an item that opens a menu of its own

When an item is chosen, `onselect` is called with its place in `items`. For an
item of a menu inside the menu, it's called with the place of the item that
opens that menu, then the item's place in that menu: `onselect(4, 2)` for
"Table" below. `off` holds the places of the items that are grey and can't be
chosen: `off=[1, (4, 2)]`.

The menu's top left corner is at `at`, which is where the mouse is unless you
give another place.

It's true when the menu was shown. It's false when there's no macOS window to
show it in, so that you can show a menu of your own with `show_menu!`.

    system_menu(window, ["Copy", "Paste", "-", "Insert" => ["Heading", "Table"]], (place...) -> println("chose ", place))
"""
system_menu(w::AbstractWindow, items::Vector, onselect; at=w.mouse, off=()) = begin
  (Sys.isapple() && !isempty(w.glfw)) || return false
  on_choice[] = onselect
  empty!(choices)
  # Nothing draws while the menu is open. So draw now what changed just before it, like a mark on the thing the menu is for.
  Base.invokelatest(redraw, w)
  with_pool() do
    menu = native_menu(items, off, ())
    # The menu goes in the window's own view, so it's dark when the window is.
    # The view measures up from its bottom edge, and the window measures down from its top.
    view = msg(nswindow(w), "contentView")
    place = NSPoint(Float64(at[1].value), Float64((w.size[2] - at[2]).value))
    ccall((:objc_msgSend, libobjc), Bool, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, NSPoint, Ptr{Cvoid}),
          menu, sel("popUpMenuPositioningItem:atLocation:inView:"), C_NULL, place, view)
  end
  # The menu uses up the release of the button that opened it, so the window never hears it go up
  for key in (Keys.mouse_right, Keys.mouse_left)
    key in w.keys && (w.keys ⊻= key)
  end
  true
end

"An NSMenu of `items`. `path` is the place of the item that opens it, or `()` for the menu itself."
native_menu(items, off, path) = begin
  menu = msg(msg(msg(cls("NSMenu"), "alloc"), "init"), "autorelease")
  send(menu, "setAutoenablesItems:", false)
  for (i, entry) in enumerate(items)
    place = (path..., i)
    title = entry isa Pair ? first(entry) : entry
    item = if title == "-"
      msg(cls("NSMenuItem"), "separatorItem")
    else
      # An item that opens a menu has nothing to tell when it's clicked
      action = entry isa Pair ? C_NULL : sel("choose:")
      made = ccall((:objc_msgSend, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                   msg(cls("NSMenuItem"), "alloc"), sel("initWithTitle:action:keyEquivalent:"), nsstring(title), action, nsstring(""))
      if entry isa Pair
        msg(made, "setSubmenu:", native_menu(last(entry), off, place))
      else
        msg(made, "setTarget:", target())
        push!(choices, place)
        send(made, "setTag:", length(choices))
      end
      (place in off || (length(place) == 1 && i in off)) && send(made, "setEnabled:", false)
      msg(made, "autorelease")
    end
    msg(menu, "addItem:", item)
  end
  menu
end

export hide_titlebar!, drag_window!, dark_mode, set_dark!, system_menu
