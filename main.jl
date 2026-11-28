# The names a page usually takes from UI.jl, in one place.
# `@use "github.com/jkroso/UI.jl"...` gives the layout, the nodes,
# drawing, pictures, fonts, the window and the ready-made components.
#
# `Item` is a row of a menu. A row of a tree stays on `Interface/Semantic/ListTree`.
# `load!` and `show!` belong to the STL viewer.
# The macOS calls, playback and the test helpers stay on `Interface/objc`, `Interface/media` and `Interface/testing`.
# The player and the recorder bring `pause!`, `speed!` and `stop!` with them.

@use "./Interface/Geometric" padding background border shadow Shadow BorderSide BorderStyle Radius rgb pt mm px Container Box Stack Column Row Scroll ScrollbarMode scroll_into_view! Image Wedge Text TextAlign width height GrowType Alignment radius

export padding, background, border, shadow, Shadow, BorderSide, BorderStyle, Radius, rgb, pt, mm, px,
       Container, Box, Stack, Column, Row, Scroll, ScrollbarMode, scroll_into_view!, Image, Wedge, Text, TextAlign,
       width, height, GrowType, Alignment, radius

@use "./Interface/Specific" ConcreteText ConcreteRect font skia_cap_height

export ConcreteText, ConcreteRect, font, skia_cap_height

@use "./Interface/abstract" SemanticUI GeometricUI ConcreteUI WrapMode Theme light dark describe describe! integrate inputs version reuse! carry! add_child! detach! mixin! window_of focus onblur tabstop tabbed! with_theme theme handled

export SemanticUI, GeometricUI, ConcreteUI, WrapMode, Theme, light, dark,
       describe, describe!, integrate, inputs, version, reuse!, carry!,
       add_child!, detach!, mixin!, window_of, focus, onblur, tabstop, tabbed!,
       with_theme, theme, handled

# `handled` is bound with the nodes. `onpinch` is bound with the window.
@use "./Interface/draw" draw ui hittest emit rect scene clipboard clipboard! popup! close_popup! show_menu! hide_menu! show_tooltip! hide_tooltip! ishovered cursor open_url invalidate_layout! set_tool! clear_tool! window_tool app_size draw_tool draw_tool_under tool_input tool_cursor inside offset! frame_stats FrameStats semantic_source viewport redraw_in! MouseScroll Pinch placed! popups with_clip with_round_clip Bubble sync_mouse! popup_at frame changed!

export draw, ui, hittest, emit, rect, scene, clipboard, clipboard!,
       popup!, close_popup!, show_menu!, hide_menu!, show_tooltip!, hide_tooltip!,
       ishovered, cursor, open_url, invalidate_layout!, set_tool!, clear_tool!,
       window_tool, app_size, draw_tool, draw_tool_under, tool_input, tool_cursor, inside, offset!,
       frame_stats, FrameStats, semantic_source, viewport, redraw_in!, MouseScroll, Pinch, placed!,
       popups, with_clip, with_round_clip, Bubble, sync_mouse!, popup_at, frame, changed!

@use "./Interface/image" image_source image_aspect ImageSource register_image has_image
@use "./Interface/fonts" register_font skia_font installed_faces weight_of weight_name isitalic
@use "./Interface/window" fills_screen fill_screen! hide_titlebar! place_window_buttons! fade_window_buttons! drag_window! dark_mode set_dark! system_menu onpinch watch_pinch! watch_swipes! swipe_button click_button! watch_drops! scrolled_by_wheel nswindow
@use "./Interface/save" save_png save_scene
@use "./Interface/inspector" LayoutInspector toggle_inspector!

export image_source, image_aspect, ImageSource, register_image, has_image,
       register_font, skia_font, installed_faces, weight_of, weight_name, isitalic,
       fills_screen, fill_screen!, hide_titlebar!, place_window_buttons!, fade_window_buttons!, drag_window!,
       dark_mode, set_dark!, system_menu, onpinch, watch_pinch!, watch_swipes!, swipe_button, click_button!, watch_drops!, scrolled_by_wheel, nswindow,
       save_png, save_scene, LayoutInspector, toggle_inspector!

@use "./Interface/Semantic" Button ButtonGroup TextInput Checkbox Toggle Slider ProgressBar RadioGroup Select Item Menu Dropdown SVG SVGPath Icon AbstractSatellite Tooltip KeyCombo Table TableHeader TableRow TableCell ListTree ItemGroup ColorPicker Inspector inspect Link STLViewer AudioPlayer VideoPlayer AudioRecorder Mermaid
@use "./Interface/Semantic/Menu" onselect
@use "./Interface/Semantic/Icon" load_icon icon_cache
@use "./Interface/Semantic/SVG" parse_svg_file render_svg
@use "./Interface/Semantic/STLViewer" Mesh read_stl read_3mf read_gltf read_model show! load!
@use "./Interface/Semantic/Player" toggle! pause! speed! card_bottom controls_show has_picture
@use "./Interface/Semantic/Recorder" record! stop!

export Button, ButtonGroup, TextInput, Checkbox, Toggle, Slider, ProgressBar, RadioGroup, Select,
       Item, Menu, onselect, Dropdown, SVG, SVGPath, parse_svg_file, render_svg,
       Icon, load_icon, icon_cache, AbstractSatellite, Tooltip, KeyCombo,
       Table, TableHeader, TableRow, TableCell, ListTree, ItemGroup,
       ColorPicker, Inspector, inspect, Link,
       STLViewer, Mesh, read_stl, read_3mf, read_gltf, read_model, show!, load!,
       AudioPlayer, VideoPlayer, toggle!, pause!, speed!, card_bottom, controls_show, has_picture,
       AudioRecorder, record!, stop!, Mermaid
