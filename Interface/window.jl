# Window chrome on macOS: hiding the title bar, moving the window by dragging
# the app's own top bar instead, dark mode and the system's own menus. None of
# it does anything on other systems.

@use GLFW
@use "github.com/jkroso/MiniFB.jl" AbstractWindow Keys redraw
@use "./objc" libobjc cls sel msg send get_value nsstring jstring with_pool
@use "github.com/jkroso/Font.jl/units" px

nswindow(w::AbstractWindow) = ccall((:glfwGetCocoaWindow, GLFW.libglfw), Ptr{Cvoid}, (GLFW.Window,), w.glfw[1])

const full_size_content = UInt(1) << 15 # NSWindowStyleMaskFullSizeContentView
const title_hidden = 1                   # NSWindowTitleHidden

"""
Hide the window's title bar, the way Finder does. The app's content then runs
up to the top edge of the window, and the close, minimise and zoom buttons
float over its top left corner, so leave about 70px × 40px clear there.
`place_window_buttons!` moves them. Without a title bar the window can only be
moved by dragging somewhere that calls `drag_window!`. Call it once the window
is open, e.g. from `onopen`.
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

# --- where the close, minimise and zoom buttons go ---------------------------------
#
# macOS puts the middle of the close button about 16px from the window's top and
# left edges. An app whose top bar is taller than that can move the buttons down,
# so they line up with what's in its bar. macOS puts them back each time it lays
# out the title bar: when the window changes size, gains or loses focus, turns
# dark or light, or leaves full screen. The window tells a small class after
# each of those, and the buttons move again before anything is drawn. Electron
# moves the buttons in the same way for its `trafficLightPosition`.

const full_screen = UInt(1) << 14        # NSWindowStyleMaskFullScreen
const close_button, minimise_button, zoom_button = 0, 1, 2   # NSWindowButton

struct NSRect
  x::Float64
  y::Float64
  width::Float64
  height::Float64
end

# On an Intel Mac, a method that gives back a struct this big has its own objc_msgSend
@eval frame_of(view) = ccall(($(QuoteNode(Sys.ARCH == :x86_64 ? :objc_msgSend_stret : :objc_msgSend)), libobjc),
                             NSRect, (Ptr{Cvoid}, Ptr{Cvoid}), view, sel("frame"))
set_frame!(view, r::NSRect) = ccall((:objc_msgSend, libobjc), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, NSRect), view, sel("setFrame:"), r)
window_button(win, kind) = ccall((:objc_msgSend, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Int), win, sel("standardWindowButton:"), kind)
"The strip along the top of the window that holds the buttons"
title_bar(close) = msg(msg(close, "superview"), "superview")

const button_places = Dict{Ptr{Cvoid},NTuple{2,Float64}}()   # each NSWindow whose buttons moved, and where its close button's middle goes
const button_watcher = Ref{Ptr{Cvoid}}(C_NULL)
const placing = Ref(false)   # true while the buttons move, so that their own moves don't move them again
# What the window tells the watcher after macOS lays out its title bar
const window_changes = ("NSWindowDidResizeNotification", "NSWindowDidBecomeKeyNotification", "NSWindowDidResignKeyNotification",
                        "NSWindowDidBecomeMainNotification", "NSWindowDidResignMainNotification",
                        "NSWindowDidExitFullScreenNotification", "NSWindowWillCloseNotification")

points(x::Real) = Float64(x)
points(x) = Float64(convert(px, x).value)

"""
Move the close, minimise and zoom buttons of a window without a title bar (see
`hide_titlebar!`) so the middle of the close button is `x` from the window's
left edge and `y` from its top. The other two keep their gaps to it. To line
the buttons up with a top bar that's 44px tall, `y` is 22px. They stay there
when macOS lays out the title bar again. In full screen they go back to where
macOS puts them.

    onopen(::App, w::Window) = place_window_buttons!(hide_titlebar!(w), 22px, 22px)
"""
place_window_buttons!(w::AbstractWindow, x, y) = begin
  (Sys.isapple() && !isempty(w.glfw)) || return w
  win = nswindow(w)
  with_pool() do
    haskey(button_places, win) || watch_window(win)
    button_places[win] = (points(x), points(y))
    # A title bar that macOS still has to lay out would put the buttons back later
    msg(msg(msg(win, "contentView"), "superview"), "layoutSubtreeIfNeeded")
    place_buttons(win)
  end
  w
end

"Put the buttons of the NSWindow `win` where `button_places` says"
place_buttons(win) = begin
  placing[] && return
  get_value(UInt, win, "styleMask") & full_screen == 0 || return
  buttons = map(kind -> window_button(win, kind), (close_button, minimise_button, zoom_button))
  any(==(C_NULL), buttons) && return
  placing[] = true
  try
    x, y = button_places[win]
    # The strip is made 2y tall, so the buttons' middles are y from its top and
    # from its bottom alike. Then it doesn't matter which edge it measures from.
    strip = title_bar(buttons[1])
    now = frame_of(strip)
    wanted = NSRect(now.x, frame_of(win).height - 2y, now.width, 2y)
    now == wanted || set_frame!(strip, wanted)
    close = frame_of(buttons[1])
    gap = frame_of(buttons[2]).x - close.x
    for (i, button) in enumerate(buttons)
      now = frame_of(button)
      wanted = NSRect(x - close.width / 2 + (i - 1) * gap, y - now.height / 2, now.width, now.height)
      now == wanted || set_frame!(button, wanted)
    end
  finally
    placing[] = false
  end
end

"""
macOS calls this after it lays out the title bar of a window whose buttons
moved, and when the window closes. It also calls it when the strip that holds
the buttons changes size, which it does when the window turns dark or light.
"""
window_changed(self::Ptr{Cvoid}, cmd::Ptr{Cvoid}, note::Ptr{Cvoid})::Cvoid = begin
  try
    name = jstring(msg(note, "name"))
    thing = msg(note, "object")
    win = startswith(name, "NSView") ? msg(thing, "window") : thing
    if name == "NSWindowWillCloseNotification"
      if haskey(button_places, win)
        delete!(button_places, win)
        for watched in (win, title_bar(window_button(win, close_button)))
          ccall((:objc_msgSend, libobjc), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                notifications(), sel("removeObserver:name:object:"), self, C_NULL, watched)
        end
      end
    # In full screen the strip sits in a window of its own, which isn't in `button_places`
    elseif haskey(button_places, win)
      place_buttons(win)
    end
  catch err
    # An error mustn't go back into macOS's own code
    @error "Couldn't move the window's buttons" exception=(err, catch_backtrace())
  end
  nothing
end

notifications() = msg(cls("NSNotificationCenter"), "defaultCenter")

"Have the NSWindow `win` tell the watcher each time macOS lays out its title bar again"
watch_window(win) = begin
  if button_watcher[] == C_NULL
    class = cls("UIWindowWatcher")
    if class == C_NULL
      class = ccall((:objc_allocateClassPair, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Cstring, Csize_t), cls("NSObject"), "UIWindowWatcher", 0)
      ccall((:objc_registerClassPair, libobjc), Cvoid, (Ptr{Cvoid},), class)
    end
    # The class outlives this file when the file is loaded again, so give it the function as it is now
    ccall((:class_replaceMethod, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Cstring), class, sel("windowChanged:"),
          @cfunction(window_changed, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid})), "v@:@")
    button_watcher[] = msg(msg(class, "alloc"), "init")
  end
  watched = [(name, win) for name in window_changes]
  close = window_button(win, close_button)
  close == C_NULL || push!(watched, ("NSViewFrameDidChangeNotification", title_bar(close)))
  for (name, thing) in watched
    ccall((:objc_msgSend, libobjc), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
          notifications(), sel("addObserver:selector:name:object:"), button_watcher[], sel("windowChanged:"), nsstring(name), thing)
  end
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

# --- a pinch on the trackpad -------------------------------------------------------
#
# GLFW, which opens the window, tells an app about the keyboard, the mouse and
# scrolling, but not about a pinch. macOS sends a pinch to the window's view as
# `magnifyWithEvent:`, which GLFW's view doesn't have. So the view's class gets
# that method here, and it passes each pinch on to `onpinch`.

const pinched = Dict{Ptr{Cvoid},WeakRef}()   # each NSWindow that passes its pinches on, and the window it's for

"""
Called while two fingers move apart or together on the trackpad. `scale` is how
much bigger the fingers ask for since the last call: 1.05 is 5% bigger and 0.95
is 5% smaller. A whole pinch is many calls with a `scale` near 1.
"""
onpinch(window, scale) = nothing

"macOS calls this on the window's view for each step of a pinch"
magnified(self::Ptr{Cvoid}, cmd::Ptr{Cvoid}, event::Ptr{Cvoid})::Cvoid = begin
  try
    ref = get(pinched, msg(event, "window"), nothing)
    w = ref === nothing ? nothing : ref.value
    w === nothing || invokelatest(onpinch, w, 1 + get_value(Float64, event, "magnification"))
  catch err
    # An error mustn't go back into macOS's own code
    @error "Couldn't pass on a pinch" exception=(err, catch_backtrace())
  end
  nothing
end

"Have macOS tell `onpinch` about each pinch in the window. Call it once the window is open."
watch_pinch!(w::AbstractWindow) = begin
  (Sys.isapple() && !isempty(w.glfw)) || return w
  win = nswindow(w)
  with_pool() do
    class = ccall((:object_getClass, libobjc), Ptr{Cvoid}, (Ptr{Cvoid},), msg(win, "contentView"))
    # The class outlives this file when the file is loaded again, so give it the function as it is now
    ccall((:class_replaceMethod, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Cstring), class, sel("magnifyWithEvent:"),
          @cfunction(magnified, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid})), "v@:@")
  end
  filter!(p -> p.second.value !== nothing, pinched)   # windows that have gone
  pinched[win] = WeakRef(w)
  w
end

# --- a mouse wheel or a trackpad ---------------------------------------------------
#
# macOS says, with each scroll, if it came in small exact steps, as from a
# trackpad, or in the whole steps of a mouse wheel. GLFW reads that but doesn't
# pass it on. Its scroll callback runs while macOS handles the scroll, so the
# event that the app handles now is that scroll.

const scroll_wheel_event = UInt(22)   # NSEventTypeScrollWheel

"""
True when the scroll that's happening now came from a mouse wheel that turns in
steps. False when it came from two fingers on a trackpad or on a Magic Mouse,
which macOS gives in small exact steps. Call it while a scroll is handled, as
from `onscroll`. On other systems, and with no scroll happening, it's false.
"""
scrolled_by_wheel() = Sys.isapple() && with_pool() do
  event = msg(msg(cls("NSApplication"), "sharedApplication"), "currentEvent")
  event != C_NULL && get_value(UInt, event, "type") == scroll_wheel_event && !get_value(Bool, event, "hasPreciseScrollingDeltas")
end

export hide_titlebar!, place_window_buttons!, drag_window!, dark_mode, set_dark!, system_menu, onpinch, watch_pinch!, scrolled_by_wheel
