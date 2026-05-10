# Scroll
#
# Demonstrates the `Scroll` geometric primitive: a fixed-size viewport
# whose single child is laid out at its natural height and translated by
# `offset` at position-time. Mouse-wheel updates `offset`; the
# scrollbar track only appears while the cursor is inside the
# viewport.
#
# Important: `Scroll` carries its state (offset, content_height, hover)
# directly on the geometric node. The describe pipeline rebuilds the
# concrete tree every frame, so the same Scroll instance must be reused
# across frames or the offset will reset. We satisfy that here by
# building the whole tree once as a `const` and pointing
# `Window.ui` at it.

@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl"...
@use "../Interface/Geometric"...
@use "../Interface/Specific"...
@use "../Interface/draw" ui draw
@use "../Interface/abstract" WrapMode
@use Colors: @colorant_str

const C_BG     = colorant"rgb(247,248,251)"
const C_PANEL  = colorant"white"
const C_BORDER = colorant"rgb(226,232,240)"
const C_STRIPE = colorant"rgb(252,253,255)"
const C_TEXT   = colorant"rgb(15,23,42)"
const C_DIM    = colorant"rgb(100,116,139)"
const C_MUTED  = colorant"rgb(148,163,184)"
const C_ACCENT = colorant"rgb(37,99,235)"

# Three row variants, each with a different fixed height. The content
# Column doesn't care -its initialize sums whatever its children's
# heights happen to be, and Scroll lays it out at that natural total.

# Each line box reserves roughly 1.7× the font cap-height so glyph
# descenders never collide with the cap area of the next line. Spacer
# Boxes between lines are unnecessary at these heights — the box's own
# vertical centring of the glyph leaves breathing room above and below.

row_compact(i, title) =
  Row(width(grow=GrowType.Grow), height(48px), padding(12px, 12px),
      Alignment.Center,
      background(iseven(i) ? C_PANEL : C_STRIPE),
      border(1px, :solid, C_BORDER),
    Box(width(40px), height(24px),
      Text(string(i), size=11pt, weight=700, color=C_ACCENT)),
    Box(height(24px),
      Text(title, size=13pt, weight=500, color=C_TEXT, wrap=WrapMode.none)))

row_detailed(i, title, subtitle) =
  Row(width(grow=GrowType.Grow), height(76px), padding(12px, 14px),
      Alignment.Center,
      background(iseven(i) ? C_PANEL : C_STRIPE),
      border(1px, :solid, C_BORDER),
    Box(width(40px), height(24px),
      Text(string(i), size=11pt, weight=700, color=C_ACCENT)),
    Column(width(grow=GrowType.Grow), Alignment.Start,
      Box(height(24px),
        Text(title, size=13pt, weight=500, color=C_TEXT, wrap=WrapMode.none)),
      Box(height(22px),
        Text(subtitle, size=11pt, weight=500, color=C_DIM, wrap=WrapMode.none))))

row_full(i, title, subtitle, meta) =
  Row(width(grow=GrowType.Grow), height(102px), padding(12px, 14px),
      Alignment.Center,
      background(iseven(i) ? C_PANEL : C_STRIPE),
      border(1px, :solid, C_BORDER),
    Box(width(40px), height(24px),
      Text(string(i), size=11pt, weight=700, color=C_ACCENT)),
    Column(width(grow=GrowType.Grow), Alignment.Start,
      Box(height(24px),
        Text(title, size=13pt, weight=600, color=C_TEXT, wrap=WrapMode.none)),
      Box(height(22px),
        Text(subtitle, size=11pt, weight=500, color=C_DIM, wrap=WrapMode.none)),
      Box(height(20px),
        Text(meta, size=10pt, weight=600, color=C_MUTED, wrap=WrapMode.none))))

# Each entry is a tuple: (title, subtitle_or_nothing, meta_or_nothing).
# A row is compact, detailed, or full depending on how many fields are
# populated.
const ITEMS = [
  ("Pick up parcel from concierge", nothing,                          nothing),
  ("Reply to RFP from Acme",         "Due tomorrow at 5pm",            "Acme · Sales"),
  ("Refactor query planner cache",   nothing,                          nothing),
  ("Email Sam about Friday's review",nothing,                          nothing),
  ("Audit dashboards for stale alerts", "12 alerts firing -3 critical", nothing),
  ("Draft Q3 hiring plan",           nothing,                          nothing),
  ("Schedule dentist",               "Last visit: 18 months ago",      nothing),
  ("Renew domain certs",             nothing,                          nothing),
  ("Triage inbound from launch post","Posted 2h ago -38 replies",     "Hacker News · Top 5"),
  ("Review pull request #4012",      nothing,                          nothing),
  ("Backup the side-project repo",   nothing,                          nothing),
  ("Fix tooltip flicker on hover",   "Repro: hover-leave-hover quickly",nothing),
  ("Update README with new install steps", nothing,                    nothing),
  ("Reach out to potential design partner", "Met at the meetup",       "Intro warm -needs follow-up"),
  ("Plan team offsite agenda",       nothing,                          nothing),
  ("Catch up on Julia changelogs",   nothing,                          nothing),
  ("Re-architect the scrollbar overlay", "Skia clip path needs work",  nothing),
  ("Decline the recruiter politely", nothing,                          nothing),
  ("Write blog post draft",          "On the staged-describe pipeline",nothing),
  ("Order birthday gift for Robin",  nothing,                          nothing)]

build_row(i, (title, subtitle, meta)) =
  meta     !== nothing ? row_full(i, title, subtitle, meta)     :
  subtitle !== nothing ? row_detailed(i, title, subtitle)        :
                         row_compact(i, title)

const ROWS = [build_row(i, ITEMS[((i - 1) % length(ITEMS)) + 1]) for i in 1:60]

# Content column. No height-grow → its initialize gives it natural height
# (sum of row heights), which is what Scroll's layout expects.
const content = Column(width(grow=GrowType.Grow), ROWS...)

# The scroll viewport. Built once and reused across frames so its
# `offset` survives between scrolls.
const scroller = Scroll(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                        background(C_PANEL),
                        border(1px, :solid, C_BORDER),
                        radius(8px),
                        content)

const root = Column(width(grow=GrowType.Grow), height(grow=GrowType.Grow),
                    padding(20px), background(C_BG), Alignment.Start,
  Row(width(grow=GrowType.Grow), height(28px), Alignment.Center,
    Box(height(24px),
      Text("Scroll demo", size=18pt, weight=700, color=C_TEXT))),
  Box(height(6px)),
  Row(width(grow=GrowType.Grow), height(20px), Alignment.Center,
    Box(height(16px),
      Text("Hover the panel and use the scroll wheel.",
           size=11pt, weight=500, color=C_DIM))),
  Box(height(14px)),
  scroller)

const window = Window(root, title="Scroll", size=(380px, 460px))
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

display(window)
