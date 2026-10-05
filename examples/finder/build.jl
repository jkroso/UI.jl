# Build the Finder example as a standalone Mac app with JuliaC:
#
#     julia --project=. examples/finder/build.jl
#
# It writes build/UI.jl Finder.app, which runs without Julia installed, checks
# it with the app's self-test, and prints how much space each part takes. JuliaC
# must be in your global environment (`] add JuliaC`), and you need a C compiler,
# such as the one in Xcode's command line tools.
#
# These environment variables change how it's built:
#
#   FINDER_CPU=apple-m1     the CPUs to compile for. apple-m1 runs on every Apple Silicon Mac.
#   FINDER_STRIP=metadata   leave out docstrings and line numbers. Add `ir` to leave out the
#                           code Julia would need to compile anything new while the app runs.
#   FINDER_TRIM=no          JuliaC's trimming: no, safe or unsafe-warn.
#   FINDER_PRUNE=1          delete the native libraries the self-test didn't load.
#   FINDER_PROJECT=path     the Julia project to build from, if not UI.jl's own.

using JuliaC

const root = normpath(joinpath(@__DIR__, "..", ".."))
const out = joinpath(root, "build")
const bundle = joinpath(out, "finder")
const app = joinpath(out, "UI.jl Finder.app")
const contents = joinpath(app, "Contents")
const program = joinpath(contents, "MacOS", "finder")

option(name, default) = get(ENV, "FINDER_$name", default)
const cpu = option("CPU", "apple-m1")
const strips = split(option("STRIP", "metadata"), ',', keepempty=false)
const trim = option("TRIM", "no")
const prune = option("PRUNE", "1") == "1"
const project = option("PROJECT", root)

rm(bundle, recursive=true, force=true)
rm(app, recursive=true, force=true)

# Kip normally keeps a compiled cache of each file it loads. Julia can't make
# those while it builds an app, so Kip includes the files directly instead.
ENV["KIP_FROZEN"] = "1"

build_time = @elapsed begin
  image = ImageRecipe(output_type="--output-exe", file=joinpath(@__DIR__, "app.jl"), project=project,
                      cpu_target=cpu, trim_mode=trim, julia_args=["--strip-$s" for s in strips])
  link = LinkRecipe(image_recipe=image, outname=joinpath(bundle, "finder"), rpath="@bundle")
  compile_products(image)
  link_products(link)
  bundle_products(BundleRecipe(link_recipe=link, output_dir=bundle))
end

# A Mac app is a folder with the program in Contents/MacOS. The program looks
# for its libraries in ../lib, so they move into Contents beside it.
mkpath(contents)
for part in readdir(bundle)
  mv(joinpath(bundle, part), joinpath(contents, part == "bin" ? "MacOS" : part))
end
rm(bundle)
write(joinpath(contents, "Info.plist"), """
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>CFBundleName</key><string>UI.jl Finder</string>
    <key>CFBundleDisplayName</key><string>UI.jl Finder</string>
    <key>CFBundleIdentifier</key><string>com.github.jkroso.ui-jl.finder</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>finder</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
  </dict>
  </plist>
  """)

"""
Run the app's self-test, and return the libraries it loaded. The test runs in a
sandbox that can't read ~/.julia, as on a Mac without Julia installed. Without
that, the app would find the libraries it wraps in ~/.julia, and a missing one
inside the app would go unnoticed.

Some packages look for their files when the app starts, even though the app
never uses them. Git is one: Kip uses it to fetch code while the app is built.
Each of those gets an empty folder of the name it looks for.
"""
self_test() = begin
  depot = joinpath(contents, "share", "julia")
  for _ in 1:20
    output, errors = IOBuffer(), IOBuffer()
    sandbox = "(version 1)(allow default)(deny file-read* (subpath \"$(joinpath(homedir(), ".julia"))\"))"
    cmd = addenv(`sandbox-exec -p $sandbox $program --self-test --libraries`, "JULIA_DEPOT_PATH" => depot)
    if success(pipeline(ignorestatus(cmd), stdout=output, stderr=errors))
      lines = split(String(take!(output)), '\n', keepempty=false)
      println(lines[1])
      return Set(realpath(l) for l in lines[2:end] if ispath(l))
    end
    problem = String(take!(errors))
    # The error quotes the name and path, with backslashes before the quotes
    m = match(r"Artifact \W*(\w+)\W* was not found by looking in the path \W*(/[^\"\\]+)", problem)
    m === nothing && error("The self-test failed:\n", first(problem, 2000))
    mkpath(m[2])
    println("Gave ", m[1], " an empty folder. The app doesn't use it.")
  end
  error("The self-test kept finding missing folders")
end

loaded = self_test()

"Every file under `dir`, apart from links"
files_in(dir) = [joinpath(d, f) for (d, _, fs) in walkdir(dir) for f in fs if !islink(joinpath(d, f))]
"Bytes used by the files under `path`"
disk_size(path) = isfile(path) ? filesize(path) : sum(filesize, files_in(path), init=0)

"""
Delete each library in the app that the self-test didn't load, and the folders
of data that only belong to those libraries. Returns how many bytes it freed.
"""
prune_libraries(loaded) = begin
  removed = 0
  for path in vcat(files_in(joinpath(contents, "lib")), files_in(joinpath(contents, "share")))
    endswith(path, ".dylib") || occursin(".dylib.", path) || continue
    realpath(path) in loaded && continue
    occursin("libjulia", basename(path)) && continue
    removed += filesize(path)
    rm(path)
  end
  for dir in readdir(joinpath(contents, "share", "julia", "artifacts"), join=true)
    isdir(dir) || continue
    any(endswith(".dylib"), files_in(dir)) && continue
    any(p -> startswith(p, dir), loaded) && continue
    # A folder with no library left holds data for one that's gone, like
    # keyboard layouts for Linux. Its package may still look for the folder when
    # the app starts, so the folder stays, empty.
    for f in readdir(dir, join=true)
      removed += isdir(f) ? sum(filesize, files_in(f), init=0) : filesize(f)
      rm(f, recursive=true)
    end
  end
  removed
end

prune && println("Pruning removed ", round(prune_libraries(loaded) / 1e6, digits=1), " MB")

# The libraries the app calls into. Each package that wraps a library loads all
# of that library's files when the app starts, so many more load than are used.
# ICU is one: Skia's package lists it, but Skia on macOS uses Apple's text APIs.
const called = ("libskia", "libglfw", "libfontconfig")

install_name(path) = String(strip(last(split(readchomp(`otool -D $path`), '\n'))))
links(path) = [String(first(split(strip(l)))) for l in split(readchomp(`otool -L $path`), '\n')[2:end]]

"""
Keep the libraries the app calls and everything they link to. Swap each other
library for an empty one with the same name, which still loads but holds no
code. Then delete what only command line tools and compilers use. Returns how
many bytes it freed.
"""
stub_unused_libraries() = begin
  artifacts = joinpath(contents, "share", "julia", "artifacts")
  dylibs = filter(p -> endswith(p, ".dylib"), files_in(artifacts))
  by_name = Dict(install_name(p) => p for p in dylibs)
  keep = Set{String}()
  queue = filter(p -> any(c -> startswith(basename(p), c), called), dylibs)
  while !isempty(queue)
    p = pop!(queue)
    p in keep && continue
    push!(keep, p)
    append!(queue, (by_name[l] for l in links(p) if haskey(by_name, l)))
  end
  before = disk_size(artifacts)
  for p in dylibs
    p in keep && continue
    stub = p * ".stub"
    run(`clang -dynamiclib -x c /dev/null -install_name $(install_name(p)) -o $stub`)
    mv(stub, p, force=true)
  end
  for dir in readdir(artifacts, join=true)
    for part in ("bin", "include", "lib/pkgconfig", "lib/cmake", "share/man", "share/doc", "share/info", "logs")
      rm(joinpath(dir, part), recursive=true, force=true)
    end
    foreach(rm, filter(endswith(".a"), files_in(dir)))
  end
  before - disk_size(artifacts)
end

prune && println("Stand-ins for unused libraries saved ", round(stub_unused_libraries() / 1e6, digits=1), " MB")

prune && self_test()

# Sign it for this Mac only, so macOS will open it
run(`codesign --force --deep --sign - $app`)

mb(n) = string(round(n / 1e6, digits=1), " MB")

println("\nBuilt in ", round(build_time / 60, digits=1), " minutes with cpu=$cpu strip=$(join(strips, ',')) trim=$trim",
        prune ? " pruned" : "")
println(app, ": ", mb(disk_size(app)))
for part in ("MacOS/finder", "lib", "share")
  println("  ", rpad(part, 14), lpad(mb(disk_size(joinpath(contents, part))), 10))
end
