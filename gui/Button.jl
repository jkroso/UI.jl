@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom

@mutable Button <: Component
@mutable ButtonGroup <: Component

dom(b::Button) = begin
  @dom[:button{css"""
               padding: .5em .75em
               font-size: .875em
               line-height: 1.25em
               font-weight: 600
               color: rgb(17, 24, 39)
               background: white
               text-align: center
               border: 1px solid #e5e7eb
               &:hover {background: rgb(249 250 251)}
               """, b.attrs...} type="button"
    b.children...]
end

dom(bg::ButtonGroup) = begin
  @dom[:div{bg.attrs..., css"""
                         display: inline-flex
                         > button {border-right: none}
                         > :first-child {border-radius: .375em 0 0 .375em}
                         > :last-child {border-radius: 0 .375em .375em 0; border-right: 1px solid #e5e7eb}
                         """}
    bg.children...]
end

adopt(bg::ButtonGroup, child::UINode) = @ui[Button child]

# @ui[Button "x"]
# @ui[ButtonGroup "Years" "Months" "Days" "Hours"]
