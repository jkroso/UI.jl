@use "../../JuliaLang/FS.jl/main.jl" Path
@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl/html.jl"
@use "github.com/jkroso/DOM.jl" Node @dom @css_str
@use "../types.jl" UINode dom

const dir = Path(@__DIR__) * "../Icons"
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
     svg = parse(MIME("text/html"), read(dir*(ui.name*".svg")))
     delete!(svg.attrs, :width)
     delete!(svg.attrs, :height)
     delete!(svg.attrs, :class)
     svg
    end]
end

# Icon(name="2-circle")
