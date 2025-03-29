@use "github.com/jkroso/Prospects.jl" @def @property @field_str
@use "github.com/jkroso/Font.jl" Font width ["units" px]
@use "../abstract" resolve ConcreteUI
@use "../Descriptive" => D
@use GeometryBasics: Point, Vec, Rect

@def mutable struct ConcreteRect <: ConcreteUI
  geometry::Rect{2,px}
  children::Vector{ConcreteUI}
end

@property ConcreteUI.firstchild = self.children[1]
@property ConcreteUI.children = getfield(self, :children)
@property ConcreteRect.width = self.geometry.widths[1]
@property ConcreteRect.height = self.geometry.widths[2]
@property ConcreteRect.left = self.geometry.origin[1]
@property ConcreteRect.top = self.geometry.origin[1]

@def mutable struct ConcreteText <: ConcreteUI
  width::px
  font::Font
end

"""
1. Fit Sizing Widths
2. Grow and Shrink Sizing Widths
3. Wrap Text
4. Fit Sizing Heights
5. Grow and Shrink Sizing Heights
6. Positions
7. Draw
"""

function resolve(ui::D.Rect, (w, h))
  children = [resolve(c, (w, h)) for c in ui.children]
  width = sum(field"width", children)
  width += ui.padding.width + ui.border.width
  between = ui.child_gap + (ismissing(ui.border.between_children) ? 0px : ui.border.between_children.width)
  width += between * max(0, length(children) - 1)
  ConcreteRect(geometry=Rect(0,0, width,0), children=children)
end

function resolve(ui::D.Text, (w, h))
  f = Font(ui.family*':'*ui.subfamily)
  ConcreteText(from=ui, width=width(ui.content, f), font=f)
end

resolve(D.Rect(D.Text("abc", subfamily="light"), D.padding(1px)), (100px, 10px))
