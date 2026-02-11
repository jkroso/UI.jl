@use "github.com/jkroso/Prospects.jl" @def
@use "../abstract" SemanticUI

@def mutable struct Menu <: SemanticUI
  items::Vector{String} = String[]
  hover::Int = 0
end

export Menu
