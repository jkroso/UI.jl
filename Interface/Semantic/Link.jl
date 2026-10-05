@use "github.com/jkroso/Prospects.jl" @def
@use "github.com/jkroso/MiniFB.jl" onkey KeyPress Keys
@use "../abstract" SemanticUI describe
@use "../draw" ishovered cursor open_url

"""
A region that opens `url` in the default browser when clicked and shows a
pointing-hand cursor. `look(hovered::Bool)` returns its geometry, so a link can
change style while the cursor is over it:

    Link("https://github.com/jkroso/UI.jl") do hovered
      Box(padding(8px), Text("Github", color=hovered ? red : black))
    end
"""
@def mutable struct Link <: SemanticUI
  url::String = ""
  look::Any = nothing
end

Link(look::Function, url::AbstractString) = Link(url=String(url), look=look)

describe(l::Link) = l.look(ishovered(l))
onkey(l::Link, ::KeyPress{Keys.mouse_left}) = open_url(l.url)
cursor(::Link) = :hand

export Link
