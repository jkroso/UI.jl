# Build the Finder example as a standalone Mac app with JuliaC:
#
#     julia --project=. examples/finder/build.jl
#
# It writes build/UI.jl Finder.app. See ../mac_app/build.jl for what the build
# needs and the settings it takes.

include("../mac_app/build.jl")

build_app(name="UI.jl Finder", program="finder", id="com.github.jkroso.ui-jl.finder",
          entry=joinpath(@__DIR__, "app.jl"))
