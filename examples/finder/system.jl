# What the operating system knows about a file: the name and kind Finder shows,
# whether Finder hides it, and its icon. On macOS these come from AppKit and
# Foundation through the Objective-C runtime. Elsewhere there are plain
# fallbacks, and `file_icon` returns `nothing` so the caller can draw its own.

@use "../../Interface/image" register_image has_image
@use "../../Interface/objc" libobjc cls sel msg nsstring jstring with_pool
@use Libdl

const macos = Sys.isapple()

# AppKit holds NSWorkspace and NSBitmapImageRep. GLFW loads it for its window,
# but a PNG-only run has no window, so load it here too.
macos && Libdl.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")

fileurl(path) = msg(cls("NSURL"), "fileURLWithPath:", nsstring(path))

"One of the file's resource values, such as \"NSURLIsHiddenKey\", or C_NULL"
resource(url, key) = begin
  value = Ref{Ptr{Cvoid}}(C_NULL)
  ok = ccall((:objc_msgSend, libobjc), Bool, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}, Ptr{Cvoid}),
             url, sel("getResourceValue:forKey:error:"), value, nsstring(key), C_NULL)
  ok ? value[] : C_NULL
end
flag(url, key) = (v = resource(url, key); v != C_NULL && ccall((:objc_msgSend, libobjc), Bool, (Ptr{Cvoid}, Ptr{Cvoid}), v, sel("boolValue")))
number(url, key) = (v = resource(url, key); v == C_NULL ? nothing : ccall((:objc_msgSend, libobjc), Int64, (Ptr{Cvoid}, Ptr{Cvoid}), v, sel("longLongValue")))

"What Finder knows about a file, read in one go when a folder is listed"
struct FileInfo
  name::String      # the name Finder shows, e.g. "Safari" for Safari.app
  kind::String      # e.g. "Folder", "PNG image", "Application"
  hidden::Bool      # Finder hides it unless you show hidden files
  package::Bool     # a folder that Finder treats as one file, like an app
end

const ext_kinds = Dict("jl" => "Julia source", "md" => "Markdown text", "txt" => "Plain text", "png" => "PNG image",
                       "jpg" => "JPEG image", "jpeg" => "JPEG image", "pdf" => "PDF document", "toml" => "TOML file",
                       "json" => "JSON", "svg" => "SVG image", "zip" => "ZIP archive", "html" => "HTML text")

file_info(path::AbstractString, isdir::Bool) = begin
  name = basename(path)
  macos || return FileInfo(name, isdir ? "Folder" : get(ext_kinds, lowercase(lstrip(splitext(name)[2], '.')), "Document"),
                           startswith(name, "."), false)
  # Finder describes what a link points to, e.g. /Applications/Safari.app
  target = islink(path) ? something(tryreal(path), path) : path
  with_pool() do
    url = fileurl(target)
    shown = jstring(resource(url, "NSURLLocalizedNameKey"))
    kind = jstring(resource(url, "NSURLLocalizedTypeDescriptionKey"))
    FileInfo(isempty(shown) ? name : shown, isempty(kind) ? "Document" : kind,
             startswith(name, ".") || flag(url, "NSURLIsHiddenKey"), isdir && flag(url, "NSURLIsPackageKey"))
  end
end

tryreal(path) = try realpath(path) catch; nothing end

"""
True for a mounted volume that Finder lists under Locations. That leaves out
hidden system volumes, like Recovery and Time Machine's snapshots.
"""
sidebar_volume(path::AbstractString) = begin
  macos || return !startswith(basename(path), ".")
  with_pool() do
    url = fileurl(path)
    flag(url, "NSURLIsVolumeKey") && !flag(url, "NSURLIsHiddenKey") &&
      (flag(url, "NSURLVolumeIsBrowsableKey") || !flag(url, "NSURLVolumeIsInternalKey"))
  end
end

"The user's locale, like \"en_AU\""
locale() = macos ? with_pool(() -> jstring(msg(msg(cls("NSLocale"), "currentLocale"), "localeIdentifier"))) :
                   first(split(get(ENV, "LANG", "en_US"), '.'))

"""
Bytes free on the volume holding `path`. On macOS this includes space the system
can reclaim, like Finder shows.
"""
available_space(path::AbstractString) = begin
  if macos
    n = with_pool(() -> number(fileurl(path), "NSURLVolumeAvailableCapacityForImportantUsageKey"))
    n === nothing || n <= 0 || return n
  end
  s = Base.Filesystem.diskstat(path)
  s.available * s.bsize
end

struct CGRect
  x::Float64
  y::Float64
  w::Float64
  h::Float64
end

"""
The key of a registered image holding the system's icon for `path`, `px` pixels
square, or `nothing` when the system has no icons to give. Plain folders and
plain files share icons by extension, so a big folder only asks the system for
a few. Apps and other packages each have their own. Fetching a new icon takes
a few milliseconds, so with `fetch=false` it only returns icons it already has.
"""
file_icon(path::AbstractString, isdir::Bool, package::Bool; px=128, fetch=true) = begin
  macos || return nothing
  ext = lowercase(splitext(path)[2])
  key = package || isdir ? "icon:$px:$path" : "icon:$px:file$ext"
  # Folders with their own icon, like ~/Downloads, are looked up by path. Plain
  # ones share the generic folder icon once it's known.
  isdir && !package && !special_folder(path) && (key = "icon:$px:folder")
  has_image(key) && return key
  fetch || return nothing
  bytes = with_pool() do
    image = msg(msg(cls("NSWorkspace"), "sharedWorkspace"), "iconForFile:", nsstring(path))
    rect = Ref(CGRect(0, 0, px/2, px/2))
    cg = ccall((:objc_msgSend, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{CGRect}, Ptr{Cvoid}, Ptr{Cvoid}),
               image, sel("CGImageForProposedRect:context:hints:"), rect, C_NULL, C_NULL)
    cg == C_NULL && return nothing
    rep = msg(msg(cls("NSBitmapImageRep"), "alloc"), "initWithCGImage:", cg)
    png = ccall((:objc_msgSend, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt, Ptr{Cvoid}),
                rep, sel("representationUsingType:properties:"), 4, msg(cls("NSDictionary"), "dictionary"))
    n = ccall((:objc_msgSend, libobjc), UInt, (Ptr{Cvoid}, Ptr{Cvoid}), png, sel("length"))
    data = copy(unsafe_wrap(Array, Ptr{UInt8}(msg(png, "bytes")), n))
    msg(rep, "release")
    data
  end
  bytes === nothing && return nothing
  register_image(key, bytes)
end

const special = Set(joinpath(homedir(), d) for d in ("Desktop", "Documents", "Downloads", "Movies", "Music",
                                                      "Pictures", "Public", "Library", "Applications"))
special_folder(path) = path in special || path == homedir() || dirname(path) == "/" || path == "/Applications"

export FileInfo, file_info, file_icon, available_space, sidebar_volume, locale
