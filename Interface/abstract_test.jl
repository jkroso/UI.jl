@use Test: @test
@use "github.com/jkroso/Prospects.jl" @def
@use "./abstract" SemanticUI GeometricUI describe describe_children integrate detach! mixin!
@use "./Geometric" Box Row width height background radius px

@def mutable struct TestRoot <: SemanticUI end
@def mutable struct TestChild <: SemanticUI end
@def mutable struct TestState <: SemanticUI
  label::String = ""
end

describe_children(::TestRoot) = [TestChild()]
describe(::TestChild) = Box(width(10px), height(10px))
integrate(::TestChild) = :child

const root = TestRoot()
const child = root.firstchild

@test child isa TestChild
@test child.parent === root
@test root.firstchild === child

const geo = convert(GeometricUI, child)
@test geo isa Box
@test geo isa GeometricUI
@test geo.width.preferred == 10px
@test geo.height.preferred == 10px
@test geo.from === child

const parent = Box(width(20px), height(20px), child)
@test parent.firstchild isa GeometricUI
@test parent.firstchild.from === child
@test parent.firstchild.parent === parent
@test integrate(child) == :child

const state = TestState(TestChild(); label="ready")
@test state.label == "ready"
@test state.firstchild isa TestChild
@test state.firstchild.parent === state

const detached = detach!(state.firstchild)
@test detached.parent === nothing
@test state.firstchild === nothing

# Several styles mixed in at once all go to the node
let row = Row()
  mixin!(row, background("red"), radius(4px))
  @test row.radius.tl == 4px
end
