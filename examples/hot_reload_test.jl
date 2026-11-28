# Tests that a change to a constant reaches every file that uses it, in
# hot_reload.jl. An app's files use its file of constants in three ways: by an
# @use line of their own, through another file that uses it, and through one
# file that hands on the names of several (as Ladder's files could, with one
# line for its twelve low files). Before, a file that the reload reached first
# through another file was done with, and kept the constant's old value.
#
#     KIP_FROZEN=1 julia --project=. examples/hot_reload_test.jl

using Kip, Logging, Test

ENV["KIP_FROZEN"] = "1"   # Kip loads each file from its source, so each has a module to load changes into

# The parts of hot_reload.jl that read a file's code and run what changed in it. The parts that
# are about its window stay out. HOT_RELOAD_FILE names another copy of the file to test.
const WINDOW_PARTS = ("GLFW", "MiniFB", "ARGS", "started", "Threads.", "entry", "KIP_FROZEN", "while true", "using Kip")
for ex in Meta.parseall(read(get(ENV, "HOT_RELOAD_FILE", joinpath(@__DIR__, "hot_reload.jl")), String)).args
  ex isa Expr || continue
  any(part -> occursin(part, string(ex)), WINDOW_PARTS) && continue
  Core.eval(@__MODULE__, ex)
end
restart!() = (restart[] = true)

"A folder of files that use each other as an app's files do, with `gap` as the value of the constant that they all use"
app_in(dir, gap) = begin
  write(joinpath(dir, "look.jl"), "export GAP, PAD\nconst GAP = $gap\nconst PAD = 3\n")
  # Uses the constants by a line of its own
  write(joinpath(dir, "flow.jl"), "@use \"./look\" exports...\nexport wide\nwide() = GAP * 2\n")
  # Hands on every name of the two files, and defines nothing
  write(joinpath(dir, "base.jl"), """
    @use "./look" => LowLook exports...
    @use "./flow" => LowFlow exports...
    for low in (LowLook, LowFlow), name in names(low)
      name === nameof(low) || Core.eval(@__MODULE__, Expr(:export, name))
    end
    """)
  # Uses the constants by a line of its own, and through flow.jl too
  write(joinpath(dir, "faces.jl"), """
    @use "./look" exports...
    @use "./flow" exports...
    export tall, gap_now
    const TALL = GAP + 10
    tall() = TALL
    gap_now() = GAP
    """)
  # Uses them only through base.jl
  write(joinpath(dir, "user.jl"), """
    @use "./base" exports...
    export room, gap_here
    const ROOM = GAP + 100
    room() = ROOM
    gap_here() = GAP
    """)
  write(joinpath(dir, "app.jl"), "@use \"./faces\" => Faces\n@use \"./user\" => User\n@use \"./flow\" => Flow\n")
  dir
end

"The value that `f()` gives in the file `name` of `dir`, with the code that's loaded now"
ask(dir, name, f) = Base.invokelatest(getglobal(Kip.modules[joinpath(dir, name)], f))
"The value of the constant `c` in the file `name` of `dir` now"
value(dir, name, c) = Base.invokelatest(getglobal, Kip.modules[joinpath(dir, name)], c)

@testset "a new value of a constant reaches each file that uses it, however it gets it" begin
  dir = app_in(realpath(mktempdir()), 1)
  Kip.require(joinpath(dir, "app.jl"))
  track!()
  @test ask(dir, "faces.jl", :tall) == 11 && ask(dir, "user.jl", :room) == 101 && ask(dir, "flow.jl", :wide) == 2
  # Save the file of constants with another value, and load what changed
  write(joinpath(dir, "look.jl"), "export GAP, PAD\nconst GAP = 5\nconst PAD = 3\n")
  with_logger(NullLogger()) do
    redirect_stdout(devnull) do
      update!(sources[joinpath(dir, "look.jl")])
    end
  end
  @test !restart[]                                # no struct changed, so no window opens again
  @test value(dir, "look.jl", :GAP) == 5 && value(dir, "look.jl", :PAD) == 3
  # A file with a line of its own for the constants
  @test ask(dir, "flow.jl", :wide) == 10
  # A file that has such a line and uses flow.jl too: the reload can reach it through flow.jl first
  @test value(dir, "faces.jl", :GAP) == 5
  @test ask(dir, "faces.jl", :gap_now) == 5       # a function that uses the constant
  @test value(dir, "faces.jl", :TALL) == 15       # a constant made from it
  @test ask(dir, "faces.jl", :tall) == 15
  # A file that gets the constants only through the file that hands them on
  @test value(dir, "base.jl", :GAP) == 5
  @test value(dir, "user.jl", :GAP) == 5
  @test ask(dir, "user.jl", :gap_here) == 5
  @test value(dir, "user.jl", :ROOM) == 105
  @test ask(dir, "user.jl", :room) == 105
end

@testset "a change to a function still reaches the files that call it, and nothing else runs again" begin
  dir = app_in(realpath(mktempdir()), 2)
  Kip.require(joinpath(dir, "app.jl"))
  track!()
  @test ask(dir, "flow.jl", :wide) == 4
  write(joinpath(dir, "flow.jl"), "@use \"./look\" exports...\nexport wide\nwide() = GAP * 3\n")
  said = mktemp() do path, io
    redirect_stdout(io) do
      update!(sources[joinpath(dir, "flow.jl")])
    end
    flush(io)
    read(path, String)
  end
  @test ask(dir, "flow.jl", :wide) == 6
  @test value(dir, "faces.jl", :TALL) == 12 && value(dir, "user.jl", :ROOM) == 102
  # No constant changed, so no file that uses flow.jl ran a line again
  @test occursin("1 change", said) && !occursin("that use", said)
end
