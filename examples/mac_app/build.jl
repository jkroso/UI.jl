# Builds one of the examples as a standalone Mac app with JuliaC. Each app has a
# build.jl that includes this file and calls `build_app`:
#
#     julia --project=. examples/finder/build.jl
#     julia --project=. examples/disk_usage/build.jl --install
#
# It writes the app into build/, checks it with the app's self-test, and prints
# how much space each part takes. The app runs without Julia installed.
# `--install` then copies it into /Applications, in place of any copy already
# there. JuliaC must be in your global environment (`] add JuliaC`), and you need
# a C compiler, such as the one in Xcode's command line tools.
#
# These environment variables change how it's built:
#
#   APP_CPU=apple-m1     the CPUs to compile for. apple-m1 runs on every Apple Silicon Mac.
#   APP_STRIP=metadata   leave out docstrings and line numbers. Add `ir` to leave out the
#                        code Julia would need to compile anything new while the app runs.
#   APP_TRIM=no          JuliaC's trimming: no, safe or unsafe-warn.
#   APP_PRUNE=1          delete the native libraries the self-test didn't load.
#   APP_PROJECT=path     the Julia project to build from, if not UI.jl's own.
#
# The app's entry point is its app.jl, which starts with mac_app/start.jl.

using JuliaC

const root = normpath(joinpath(@__DIR__, "..", ".."))
const out = joinpath(root, "build")

option(name, default) = get(ENV, "APP_$name", default)
const cpu = option("CPU", "apple-m1")
const strips = split(option("STRIP", "metadata"), ',', keepempty=false)
const trim = option("TRIM", "no")
const prune = option("PRUNE", "1") == "1"

"""
A new folder with a copy of `dir`'s project files and nothing else. JuliaC
copies all of the project folder it's given, and UI.jl's holds build/, where
the apps are.
"""
project_files(dir) = begin
  copy = mktempdir()
  for f in readdir(dir)
    occursin(r"^(Julia)?(Project|Manifest|LocalPreferences).*\.toml$", f) && cp(joinpath(dir, f), joinpath(copy, f))
  end
  copy
end

const project = project_files(option("PROJECT", root))

"""
Build `entry` into build/`name`.app, with the program in Contents/MacOS/`program`.
`id` is its bundle identifier. `threads` sets how many threads the app runs
with, in the form of Julia's `--threads` option. `icon` is a PNG 1024 pixels
square to show for the app. `plist` holds more keys for its Info.plist. Returns
the path to the app.
"""
build_app(; name, program, id, entry, threads=nothing, icon=nothing, plist="") = begin
  bundle = joinpath(out, program)
  app = joinpath(out, name * ".app")
  contents = joinpath(app, "Contents")
  rm(bundle, recursive=true, force=true)
  rm(app, recursive=true, force=true)

  # Kip normally keeps a compiled cache of each file it loads. Julia can't make
  # those while it builds an app, so Kip includes the files directly instead.
  ENV["KIP_FROZEN"] = "1"

  options = threads === nothing ? Dict{String,String}() : Dict("threads" => threads)
  build_time = @elapsed begin
    image = ImageRecipe(output_type="--output-exe", file=entry, project=project, cpu_target=cpu,
                        trim_mode=trim, julia_args=["--strip-$s" for s in strips], jl_options=options)
    link = LinkRecipe(image_recipe=image, outname=joinpath(bundle, program), rpath="@bundle")
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
  if icon !== nothing
    mkpath(joinpath(contents, "Resources"))
    make_icns(icon, joinpath(contents, "Resources", "AppIcon.icns"))
    plist = "  <key>CFBundleIconFile</key><string>AppIcon</string>\n" * plist
  end
  write(joinpath(contents, "Info.plist"), """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleName</key><string>$name</string>
      <key>CFBundleDisplayName</key><string>$name</string>
      <key>CFBundleIdentifier</key><string>$id</string>
      <key>CFBundleVersion</key><string>1</string>
      <key>CFBundleShortVersionString</key><string>1.0</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleExecutable</key><string>$program</string>
      <key>LSMinimumSystemVersion</key><string>12.0</string>
      <key>NSHighResolutionCapable</key><true/>
    $(plist)</dict>
    </plist>
    """)

  executable = joinpath(contents, "MacOS", program)
  loaded = self_test(contents, executable)
  if prune
    println("Pruning removed ", mb(prune_libraries(contents, loaded)))
    println("Stand-ins for unused libraries saved ", mb(stub_unused_libraries(contents)))
    self_test(contents, executable)
  end

  # Sign it for this Mac only, so macOS will open it
  run(`codesign --force --deep --sign - $app`)

  println("\nBuilt in ", round(build_time / 60, digits=1), " minutes with cpu=$cpu strip=$(join(strips, ',')) trim=$trim",
          prune ? " pruned" : "")
  println(app, ": ", mb(disk_size(app)))
  for part in ("MacOS/$program", "lib", "share")
    println("  ", rpad(part, 18), lpad(mb(disk_size(joinpath(contents, part))), 10))
  end
  "--install" in ARGS && install(app)
  app
end

mb(n) = string(round(n / 1e6, digits=1), " MB")

"Make the .icns file `icns` from `png`, with each of the sizes macOS shows icons at"
make_icns(png, icns) = begin
  set = joinpath(mktempdir(), "AppIcon.iconset")
  mkpath(set)
  for points in (16, 32, 128, 256, 512), scale in (1, 2)
    file = joinpath(set, "icon_$(points)x$(points)$(scale == 2 ? "@2x" : "").png")
    run(pipeline(`sips -z $(points * scale) $(points * scale) $png --out $file`, stdout=devnull))
  end
  run(`iconutil -c icns $set -o $icns`)
end

"""
Run the app's self-test, and return the libraries it loaded. The test runs in a
sandbox that can't read ~/.julia, ~/.kip or UI.jl's own files, as on a Mac
without them. Without that, the app would find the libraries it wraps in
~/.julia, or icons in UI.jl's folder, and a missing one inside the app would go
unnoticed.

Some packages look for their files when the app starts, even though the app
never uses them. Git is one: Kip uses it to fetch code while the app is built.
Each of those gets an empty folder of the name it looks for.
"""
self_test(contents, executable) = begin
  depot = joinpath(contents, "share", "julia")
  # The app can still look at UI.jl's folders, since it sits inside one, but it
  # can't read what's in them
  sandbox = """(version 1)(allow default)
    (deny file-read* (subpath "$(joinpath(homedir(), ".julia"))") (subpath "$(joinpath(homedir(), ".kip"))"))
    (deny file-read-data (subpath "$(rstrip(root, '/'))"))
    (allow file-read-data (subpath "$out"))"""
  for _ in 1:20
    output, errors = IOBuffer(), IOBuffer()
    cmd = addenv(`sandbox-exec -p $sandbox $executable --self-test --libraries`, "JULIA_DEPOT_PATH" => depot)
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

"Every file under `dir`, apart from links"
files_in(dir) = [joinpath(d, f) for (d, _, fs) in walkdir(dir) for f in fs if !islink(joinpath(d, f))]
"Bytes used by the files under `path`"
disk_size(path) = isfile(path) ? filesize(path) : sum(filesize, files_in(path), init=0)

"""
Delete each library in the app that the self-test didn't load, and the folders
of data that only belong to those libraries. Returns how many bytes it freed.
"""
prune_libraries(contents, loaded) = begin
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
stub_unused_libraries(contents) = begin
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

const lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"""
Copy `app` into /Applications, in place of any copy already there. Then tell
macOS about it, so the Dock and Finder show its new icon.
"""
install(app) = begin
  target = joinpath("/Applications", basename(app))
  rm(target, recursive=true, force=true)
  run(`ditto $app $target`)
  run(`$lsregister -f $target`)
  println("Installed ", target)
end
