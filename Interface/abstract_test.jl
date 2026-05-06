@use "github.com/jkroso/Rutherford.jl/test.jl" @test
@use "github.com/jkroso/Prospects.jl" @def
@use "./abstract" SemanticUI GeometricUI describe describe_children
@use "./Geometric" Box width height px

@def mutable struct TestRoot <: SemanticUI end
@def mutable struct TestChild <: SemanticUI end

describe_children(::TestRoot) = [TestChild()]
describe(::TestChild) = Box(width(10px), height(10px))

const root = TestRoot()
const child = root.firstchild

@test child isa TestChild
@test child.parent === root
@test root.firstchild === child

const geo = convert(GeometricUI, child)
@test geo isa GeometricUI
@test geo.from === child

const parent = Box(width(20px), height(20px), child)
@test parent.firstchild isa GeometricUI
@test parent.firstchild.from === child
