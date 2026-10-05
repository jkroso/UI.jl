# Clay Website
#
# A port of the website for Clay, Nic Barker's C layout library
# (https://www.nicbarker.com/clay), to UI.jl. The page layout follows Clay's
# `clay-official-website` example (zlib licence, © 2024 Nic Barker). The text
# is new and describes UI.jl, since UI.jl is what's laying this window out.
#
# Things to try:
#   - Make the window narrower than 750px to get the mobile layout.
#   - Hover the header links and the renderer buttons.
#   - Scroll with the mouse wheel, the arrow keys or by dragging the scrollbar.
#   - Press d to open the layout inspector.
#
# The page uses these UI.jl features: fit, grow and percentage sizing,
# `justify` for alignment along a Row or Column, per-side borders and
# borders between children, `Image`, fonts loaded from files, `Link`,
# `ishovered`, a `Scroll` with a draggable scrollbar, `viewport` for
# responsive layout and `frame_stats` for the live timings.

@use "github.com/jkroso/Prospects.jl" @def @property
@use "github.com/jkroso/Font.jl/units" em
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/abstract" SemanticUI WrapMode describe reuse! window_of
@use "../Interface/draw" ui draw ishovered cursor open_url frame_stats viewport
@use "../Interface/fonts" register_font
@use "../Interface/inspector" toggle_inspector!
@use "../Interface/save" save_png
@use "../Interface/Semantic/Link" Link
@use "../Interface/Semantic/Icon" Icon
@use Colors: @colorant_str, RGBA, Colorant, weighted_color_mean

const assets = joinpath(@__DIR__, "assets")
const TITLE_FONT = register_font(joinpath(assets, "fonts", "Calistoga-Regular.ttf"))
const BODY_FONT = register_font(joinpath(assets, "fonts", "Quicksand-Bold.ttf"))
const CODE_FONT = "Menlo"

# --- palette (the same colours as Clay's site) ---------------------------

const LIGHT       = colorant"rgb(244,235,230)"
const LIGHT_HOVER = colorant"rgb(224,215,210)"
const RED         = colorant"rgb(168,66,28)"
const RED_HOVER   = colorant"rgb(148,46,8)"
const ORANGE      = colorant"rgb(225,138,50)"
const INK         = colorant"rgb(61,26,5)"
const STRIPES     = colorant"rgb(240,213,137)", colorant"rgb(236,189,80)", colorant"rgb(225,138,50)",
                    colorant"rgb(223,110,44)", colorant"rgb(168,66,28)"
const BLOBS       = colorant"rgb(240,189,100)", colorant"rgb(236,159,70)", colorant"rgb(225,138,50)",
                    colorant"rgb(203,100,44)", colorant"rgb(168,66,28)"

# --- content ---------------------------------------------------------------

const HERO = "UI.jl is a flex-box style layout library for Julia that turns your data into pixels in a few clear steps."
const TAGLINE = "Every box in this window was placed by UI.jl."
const FEATURES = ["Flexible sizing rules", "Text that wraps to fit", "Pure Julia layout engine",
                  "Drawn with Skia", "Hover, click and scroll"]
const LAYOUT_LINES = countlines(joinpath(@__DIR__, "..", "Interface", "Specific", "main.jl"))
const DEMO_TEXT = "These two panels trade space every second, and this text wraps again on every frame to fit."
const INSPECTOR_SHOT = joinpath(assets, "inspector.png")

# --- text helpers ----------------------------------------------------------

title(s, size; color=RED) = Text(s, size=size, family=TITLE_FONT, color=color, lineheight=1.1em)
body(s; size=28px, color=RED, align=TextAlign.Left) =
  Text(s, size=size, family=BODY_FONT, color=color, lineheight=1.05em, align=align)
label(s, size, color) = Text(s, size=size, family=BODY_FONT, color=color, wrap=WrapMode.none)

"Equal parts `a` and `b` when t is 0.5, all `b` when t is 1"
blend(a, b, t) = weighted_color_mean(1 - t, a, b)

"Goes from 0 up to 1 and back down every two seconds, like the original's animation"
pulse(t=time()) = (v = mod(t, 2.0); v < 1 ? v : 2 - v)

# --- semantic layer ----------------------------------------------------------
#
# The parts of the page with state or behaviour. Everything else is geometry
# that `describe(::Website)` rebuilds every frame.

@def mutable struct Website <: SemanticUI
  scroll::Scroll = Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow), name="PageScroll",
                          scrollbar=ScrollbarMode.always, scrollbar_width=10px,
                          scrollbar_color=RGBA(225/255, 138/255, 50/255, 0.5),
                          scrollbar_track=RGBA(0, 0, 0, 0))
  renderer::Symbol = :window
  saved::String = ""
  # The size to lay out at when the page isn't in a window, e.g. for a PNG
  size::Tuple{px,px} = (1280px, 800px)
end

@def mutable struct RendererButton <: SemanticUI
  label::String = ""
  renderer::Symbol = :window
end

@property Website.examples = self.children[1]::Link
@property Website.docs = self.children[2]::Link
@property Website.clay = self.children[3]::Link
@property Website.github = self.children[4]::Link
@property Website.window_button = self.children[5]::RendererButton
@property Website.png_button = self.children[6]::RendererButton
@property Website.saved_link = self.children[7]::Link

nav_look(name) = hovered -> Box(padding(8px), label(name, 24px, hovered ? RED : INK))

button_look(name) = hovered ->
  Box(padding(16px, 6px), radius(10px), border(2px, :solid, RED),
      background(hovered ? LIGHT_HOVER : LIGHT), label(name, 24px, INK))

saved_look(site) = hovered ->
  Box(width(300px), padding(4px), body("Saved $(basename(site.saved)). Click to open it.",
                                       size=20px, color=hovered ? RED : ORANGE))

build_site() = begin
  site = Website(
    Link(nav_look("Examples"), "https://github.com/jkroso/UI.jl/tree/main/examples"),
    Link(nav_look("Docs"), "https://github.com/jkroso/UI.jl#readme"),
    Link(button_look("Clay"), "https://www.nicbarker.com/clay"),
    Link(button_look("Github"), "https://github.com/jkroso/UI.jl"),
    RendererButton(label="Window renderer", renderer=:window),
    RendererButton(label="PNG renderer", renderer=:png),
    Link(url=""))
  site.saved_link.look = saved_look(site)
  site
end

"The size the page is being laid out at"
page_size(site::Website) = something(viewport(site), site.size)

describe(b::RendererButton) = begin
  site = b.parent::Website
  active = site.renderer == b.renderer
  hovered = ishovered(b)
  fill = active ? (hovered ? RED_HOVER : RED) : (hovered ? LIGHT_HOVER : LIGHT)
  Box(width(300px), padding(16px), radius(10px), Alignment.Start, background(fill),
      border(2px, :solid, active ? fill : RED),
      body(b.label, color=active ? LIGHT : RED))
end

cursor(::RendererButton) = :hand
onkey(b::RendererButton, ::KeyPress{Keys.mouse_left}) = use_renderer!(b.parent::Website, b.renderer)

"""
Switch renderer. The window renderer is the live one you're looking at. The
PNG renderer draws the same layout off screen and writes it to a file.
"""
use_renderer!(site::Website, renderer::Symbol) = begin
  site.renderer = renderer
  renderer == :png || return
  size = Tuple(page_size(site))
  path = joinpath(tempdir(), "ui_jl_website.png")
  save_png(path, size) do ctx, size
    draw(ctx, size, describe(describe(site), size))
  end
  site.saved = path
  site.saved_link.url = path
end

# --- geometry: the header ---------------------------------------------------

header(site, mobile) = Row(width(grow=GrowType.Grow), height(50px), padding(32px, 0px), child_gap=16px,
    name="Header",
  Box(label("UI.jl", 24px, INK), name="Logo"),
  Box(width(grow=GrowType.Grow), name="Spacer"),
  (mobile ? () : (site.examples, site.docs))...,
  site.clay,
  site.github)

stripes() = [Box(width(grow=GrowType.Grow), height(4px), background(c), name="Stripe$i")
              for (i, c) in enumerate(STRIPES)]

# --- geometry: page sections -----------------------------------------------

spacer(h) = Box(width(grow=GrowType.Grow), height(h), name="Spacer")

"Half the width on a wide screen, all of it on a narrow one"
half(mobile) = mobile ? width(grow=GrowType.Grow) : width(percent=0.5)

"A section that's at least one screen tall, with a red line down each side"
framed(h, children...; name="") =
  Row(width(grow=GrowType.Grow), height(min=h), padding(50px, 0px), name=name,
    Row(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(32px), child_gap=32px,
        border(2px, :solid, RED)[:left, :right], name="Frame", children...))

# snippet:start
"One of the bordered feature rows on the landing page"
blob(i, text, size) =
  Row(width(grow=GrowType.Grow, max=480px), padding(16px),
      child_gap=16px, radius(10px), name="Feature",
      border(2px, :solid, BLOBS[i]),
    Icon("check-circle-fill", color=BLOBS[i], size=32px),
    body(text, size=size, color=BLOBS[i]))

blobs(size) = [blob(i, text, size)
               for (i, text) in enumerate(FEATURES)]
# snippet:end

landing(h, mobile) = mobile ?
  Column(width(grow=GrowType.Grow), height(min=h-70px), padding(32px, 16px, 32px, 16px),
         child_gap=32px, justify=Alignment.Center, name="Landing",
    Column(width(grow=GrowType.Grow), child_gap=8px, Alignment.Start, name="HeroText",
      title(HERO, 48px), spacer(32px), body(TAGLINE, size=32px, color=ORANGE)),
    Column(width(grow=GrowType.Grow), child_gap=16px, name="Features", blobs(28px)...)) :
  framed(h-70px, name="Landing",
    Column(width(percent=0.55), child_gap=8px, Alignment.Start, name="HeroText",
      title(HERO, 56px), spacer(32px), body(TAGLINE, size=36px, color=ORANGE)),
    Column(width(percent=0.45), child_gap=16px, name="Features", blobs(32px)...))

feature_blocks(mobile) = begin
  pad = mobile ? padding(32px, 16px, 32px, 16px) : padding(32px, 50px, 32px, 50px)
  part(name, children...) = Column(half(mobile), pad, child_gap=16px, Alignment.Start, name=name, children...)
  left = part("EngineBlock", Box(padding(8px, 4px), radius(8px), background(RED), label("@use \"UI.jl/Interface\"", 24px, LIGHT)),
              body("The layout engine is $LAYOUT_LINES lines of Julia.", size=24px),
              body("Text is measured with Font.jl and drawn with Skia, so it wraps where it's drawn.", size=24px))
  right = part("RendererBlock", body("Two renderers.", size=24px, color=ORANGE),
               body("Lay out once, then draw to a live window or to a PNG file.", size=24px),
               body("Concrete layout is just positioned boxes and text, so a new backend only walks one tree.", size=24px))
  between = border(2px, :solid, RED, between=true)[:between]
  mobile ? Column(width(grow=GrowType.Grow), between, name="FeatureBlocks", left, right) :
           Row(width(grow=GrowType.Grow), between, name="FeatureBlocks", left, right)
end

"Source lines of the snippet marked in this file"
snippet() = begin
  lines = readlines(@__FILE__)
  a = findfirst(==("# snippet:start"), lines)
  b = findfirst(==("# snippet:end"), lines)
  lines[a+1:b-1]
end

const SYNTAX = [r"^#.*" => colorant"rgb(128,140,150)",
                r"^\"[^\"]*\"" => colorant"rgb(152,195,121)",
                r"^\b(function|end|for|in|if|else|begin|let|const|do|return)\b" => colorant"rgb(198,120,221)",
                r"^[0-9][0-9.]*(px|em)?" => colorant"rgb(209,154,102)",
                r"^[A-Za-z_][A-Za-z0-9_!]*(?=\()" => colorant"rgb(97,175,239)",
                r"^[A-Za-z_][A-Za-z0-9_!]*" => colorant"rgb(220,223,228)",
                r"^\s+" => colorant"rgb(220,223,228)",
                r"^." => colorant"rgb(171,178,191)"]

"Split a line of Julia into coloured tokens"
tokens(line) = begin
  out = Pair{String,Colorant}[]
  rest = line
  while !isempty(rest)
    for (re, colour) in SYNTAX
      m = match(re, rest)
      m === nothing && continue
      push!(out, String(m.match) => colour)
      rest = SubString(rest, ncodeunits(m.match) + 1)
      break
    end
  end
  out
end

code_line(line) = Row(height(19px), Alignment.End, name="CodeLine",
  (Box(Text(tok, size=13px, family=CODE_FONT, color=colour, wrap=WrapMode.none)) for (tok, colour) in tokens(line))...)

"A dark editor-style panel showing real code from this file"
code_panel() =
  Column(width(grow=GrowType.Grow, max=568px), padding(20px), radius(10px), Alignment.Start,
         background(colorant"rgb(43,37,34)"), clip=true, name="CodePanel",
    Row(child_gap=8px, (Box(width(12px), height(12px), radius(6px), background(c))
                        for c in (colorant"rgb(237,94,87)", colorant"rgb(245,190,79)", colorant"rgb(98,196,84)"))...),
    spacer(16px),
    (code_line(l) for l in snippet())...)

declarative(h, mobile) = begin
  text = Column(half(mobile),
                child_gap=16px, Alignment.Start, name="SyntaxText",
    title("Declarative Syntax", mobile ? 48px : 52px), spacer(0px),
    body("Describe a layout by nesting Rows, Columns and Boxes, then let UI.jl work out the sizes."),
    body("Components are ordinary Julia functions and types, so loops and conditionals just work."),
    body("Semantic nodes keep their state between frames while their geometry is rebuilt."))
  panel = Column(half(mobile), name="SyntaxPanel", code_panel())
  mobile ? Column(width(grow=GrowType.Grow), height(min=h-50px), padding(32px, 16px, 32px, 16px),
                  child_gap=24px, justify=Alignment.Center, name="Declarative", text, panel) :
           framed(h-50px, name="Declarative", text, panel)
end

timings(site) = begin
  w = window_of(site)
  w === nothing && return "Timings appear here when the page runs in a window."
  s = frame_stats(w)
  "The last frame laid out $(s.elements) elements in $(round(s.layout, digits=1)) ms and drew them in $(round(s.draw, digits=1)) ms."
end

performance(site, h, mobile, t) = begin
  text = Column(half(mobile),
                child_gap=16px, Alignment.Start, name="PerformanceText",
    title("Rebuilt Every Frame", mobile ? 48px : 52px, color=LIGHT), spacer(0px),
    body("This window describes and lays out every element on every frame.", color=LIGHT),
    body(timings(site), color=LIGHT),
    body("So an animation is just data that changes over time, like the panels here.", color=LIGHT))
  pad = mobile ? 16px : 32px
  demo = Row(width(grow=GrowType.Grow), height(400px), border(2px, :solid, LIGHT), name="AnimationDemo",
    Box(width(percent=(mobile ? 0.35 : 0.3) + (mobile ? 0.3 : 0.4) * t), height(grow=GrowType.Grow),
        padding(pad), background(blend(RED, ORANGE, t)), name="DemoLeft",
      title(DEMO_TEXT, 24px, color=LIGHT)),
    Box(width(grow=GrowType.Grow), height(grow=GrowType.Grow), padding(pad), background(blend(ORANGE, RED, t)),
        name="DemoRight",
      title(DEMO_TEXT, 24px, color=LIGHT)))
  demo_column = Column(half(mobile), name="DemoColumn", demo)
  mobile ?
    Column(width(grow=GrowType.Grow), height(min=h-50px), padding(32px, 16px, 32px, 16px), child_gap=32px,
           background(RED), justify=Alignment.Center, name="Performance", text, demo_column) :
    Row(width(grow=GrowType.Grow), height(min=h-50px), padding(32px, 82px, 32px, 82px), child_gap=64px,
        background(RED), name="Performance", text, demo_column)
end

renderers(site, h, mobile) = begin
  text = Column(half(mobile),
                child_gap=16px, Alignment.Start, name="RendererText",
    title("Render Anywhere", mobile ? 48px : 52px), spacer(0px),
    body("describe() resolves geometry into boxes, text and images at absolute positions."),
    body("draw() walks that tree with Skia. Another backend would walk the same tree."),
    body("Try it: the same layout can go to this window or to a PNG file."))
  buttons = Column(half(mobile),
                   child_gap=16px, mobile ? Alignment.Start : Alignment.Center, name="RendererButtons",
    body("Pick a renderer", size=36px, color=ORANGE, align=mobile ? TextAlign.Left : TextAlign.Center),
    spacer(16px),
    site.window_button,
    site.png_button,
    (isempty(site.saved) ? () : (site.saved_link,))...)
  mobile ? Column(width(grow=GrowType.Grow), height(min=h-50px), padding(32px, 16px, 32px, 16px),
                  child_gap=32px, justify=Alignment.Center, name="Renderers", text, buttons) :
           framed(h-50px, name="Renderers", text, buttons)
end

inspector_page(h) =
  Row(width(grow=GrowType.Grow), height(min=h-50px), padding(32px, 82px, 32px, 82px), child_gap=64px,
      background(RED), name="InspectorPage",
    Column(width(percent=0.5), child_gap=16px, Alignment.Start, name="InspectorText",
      title("Layout Inspector", 52px, color=LIGHT), spacer(0px),
      body("UI.jl can show your layout tree beside your app while it runs.", color=LIGHT),
      body("Hover any element to see its box, its size and the rules that sized it.", color=LIGHT),
      spacer(16px),
      body("Press d to open it now.", size=32px, color=ORANGE)),
    Column(width(percent=0.5), name="InspectorShot",
      (isfile(INSPECTOR_SHOT) ? (Image(INSPECTOR_SHOT, width(grow=GrowType.Grow, max=558px), radius(8px)),) : ())...))

# --- geometry: the whole page ------------------------------------------------

describe(site::Website) = begin
  w, h = page_size(site)
  mobile = w < 750px
  t = pulse()
  sections = mobile ?
    [landing(h, true), feature_blocks(true), declarative(h, true), performance(site, h, true, t),
     renderers(site, h, true)] :
    [landing(h, false), feature_blocks(false), declarative(h, false), performance(site, h, false, t),
     renderers(site, h, false), inspector_page(h)]
  Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow), background(LIGHT), Alignment.Start,
         name="Page",
    header(site, mobile),
    stripes()...,
    reuse!(site.scroll,
      Column(width(grow=GrowType.Grow), border(2px, :solid, RED, between=true)[:between],
             name="Sections", sections...)))
end

# --- window ------------------------------------------------------------------

const site = build_site()

if abspath(PROGRAM_FILE) == @__FILE__
  const window = Window(site, title="UI.jl · a port of Clay's website", size=(1280px, 800px), animating=true)
  onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)
  onkey(w::Window, ::KeyPress{Keys.d}) = toggle_inspector!(w)
  display(window)
end
