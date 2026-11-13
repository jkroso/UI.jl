@use Test: @test
@use "./testing" pixels difference

# The first four examples each save a picture of themselves beside their code. Run each one and
# compare its new picture with the one that's kept. A change to the layout or the drawing that
# moves or recolours something shows up here. If the change is one you want, run the example by
# itself to keep its new picture: `julia --project=. examples/02_styling.jl`.
for name in ("01_layout_basics", "02_styling", "03_flex_layout", "04_text_wrapping")
  file = joinpath(@__DIR__, "..", "examples", name * ".jl")
  picture = joinpath(@__DIR__, "..", "examples", name * ".png")
  kept = read(picture)
  was = pixels(picture)
  example = Module(Symbol(name))
  Core.eval(example, :(using Kip))
  redirect_stdout(devnull) do       # the examples print what they lay out
    Base.include(example, file)     # this saves the new picture over the kept one
  end
  now = pixels(picture)
  write(picture, kept)              # put the kept one back, whatever the result
  changed = difference(was, now)
  changed > 0.001 && @info "$name.png changed" pixels_changed="$(round(100changed, digits=2))%"
  @test changed <= 0.001
end
