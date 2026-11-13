# Runs every test file in one go: `julia --project=. test.jl`
# Give it words to run only the files whose paths have one of them: `julia --project=. test.jl Slider layout`
using Kip, Test

const here = @__DIR__
const files = sort!([joinpath(dir, f) for (dir, _, fs) in walkdir(joinpath(here, "Interface")) for f in fs
                     if endswith(f, "_test.jl") || f == "test.jl"])
const wanted = isempty(ARGS) ? files : filter(f -> any(word -> occursin(word, f), ARGS), files)

# Each file gets a module of its own, so that two files can use one name
run_file(file) = @testset "$(relpath(file, here))" begin
  m = Module(gensym(:test))
  Core.eval(m, :(using Kip; include(path) = Base.include($m, path)))
  Base.include(m, file)
end

@testset "UI.jl" begin
  foreach(run_file, wanted)
end
