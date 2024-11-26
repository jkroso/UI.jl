@use "github.com/jkroso/Prospects.jl" @mutable dissoc assoc
@use "github.com/jkroso/DOM.jl/html.jl"
@use "github.com/jkroso/DOM.jl" Node @dom @css_str
@use "../types.jl" UINode dom

const dir = normpath(joinpath(@__DIR__(), "../Icons"))
const cache = Dict{String,Node}()

@mutable Icon(name::String) <: UINode

dom(ui::Icon) = begin
  @dom[:icon css"""
             min-height: 1rem
             min-width: 1rem
             display: flex
             align-content: center
             justify-content: center
             align-items: center
             """
    get!(cache, ui.name) do
     svg = parse(MIME("text/html"), read(joinpath(dir, ui.name*".svg")))
     assoc(svg, :attrs, dissoc(svg.attrs, :class))
    end]
end

# Icon(name="chevron-right")
