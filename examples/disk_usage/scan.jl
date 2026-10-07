# Finding out how much disk space each file and folder uses.
#
# Worker threads list folders and send back what they found. The thread that
# calls `step!`, which is the window's, adds that to the tree of Items, so the
# tree only ever changes on one thread. `step!` takes a time limit, so a window
# can draw between steps and show the picture filling in. Folders are listed in
# about the order they're found, so the top of the tree appears first.
#
# Julia gives a script one worker thread besides the one it runs on. Start it
# with more, like `julia -t auto`, and it lists several folders at once. When
# there's no worker thread to use, `step!` lists the folders itself.

"A file or folder, and the disk space it uses"
mutable struct Item
  name::String                  # the whole path for the folder a scan starts at
  parent::Union{Nothing,Item}
  folder::Bool
  bytes::Int64                  # space on disk. For a folder, that of everything in it found so far.
  files::Int                    # files in it found so far. 1 for a file.
  children::Vector{Item}
  read::Bool                    # a folder whose contents have been listed
  denied::Bool                  # a folder that couldn't be listed
  sorted::Bool                  # its children are in order, biggest first
  asked::Int                    # how many times it's been sent to be listed
end

"Files have no children, so they all share this empty list"
const NO_CHILDREN = Item[]

Item(name, parent, folder, bytes) =
  Item(name, parent, folder, bytes, folder ? 0 : 1, folder ? Item[] : NO_CHILDREN, !folder, false, true, 0)

path(item::Item) = item.parent === nothing ? item.name : joinpath(path(item.parent), item.name)

"The space a file takes up on disk, which can be less than its length for sparse files"
used(st) = Int64(st.blocks) * 512

"`item`'s children, biggest first"
sorted(item::Item) = begin
  item.sorted || (sort!(item.children, by=c -> c.bytes, rev=true); item.sorted = true)
  item.children
end

"`item` and the folders it's in, from the top down"
lineage(item::Item) = begin
  out = Item[]
  while item !== nothing
    pushfirst!(out, item)
    item = item.parent
  end
  out
end

"True when `item` is `ancestor` or is inside it"
within(item, ancestor) = begin
  while item !== nothing
    item === ancestor && return true
    item = item.parent
  end
  false
end

# --- listing a folder ------------------------------------------------------------
#
# This part runs on the worker threads. It only reads the folder's path, so it
# never touches an Item that the tree's thread might be changing.

"One thing in a folder, as a worker found it"
struct Entry
  name::String
  folder::Bool
  bytes::Int64
  device::UInt64
  inode::UInt64
  links::Int
end

"What's in `folder`, which was asked for the `asked`th time"
struct Listing
  folder::Item
  asked::Int
  entries::Vector{Entry}
  denied::Bool
end

list(folder, asked, dir) = try
  entries = Entry[]
  for name in readdir(dir)
    st = try lstat(joinpath(dir, name)) catch; continue end
    ispath(st) || continue
    push!(entries, Entry(name, isdir(st), used(st), st.device, st.inode, st.nlink))
  end
  Listing(folder, asked, entries, false)
catch
  Listing(folder, asked, Entry[], true)
end

"List each folder sent to `jobs` until it's closed"
work(jobs, done) = for (folder, asked, dir) in jobs
  put!(done, list(folder, asked, dir))
end

# --- the scan ------------------------------------------------------------------

# Folders the scan never enters: other disks, and the macOS folder that holds
# the files in /Users and /Applications a second time
const SKIP = Set(["/Volumes", "/System/Volumes", "/dev", "/proc", "/sys"])

mutable struct Scan
  root::Item
  # Folders for the workers to list, and what they found. `queue` holds them
  # instead when there are no workers.
  jobs::Channel{Tuple{Item,Int,String}}
  done::Channel{Listing}
  queue::Vector{Tuple{Item,Int,String}}
  waiting::Int                           # folders asked for and not added yet
  # Files with more than one hard link, and the item that counted each one, so
  # they're counted once
  seen::Dict{Tuple{UInt64,UInt64},Item}
  disks::Set{UInt64}                     # the scan doesn't leave these
  started::Float64
  finished::Float64                      # 0 while it's running
  denied::Int                            # folders it couldn't read
end

"""
True when list jobs can go to worker threads. The workers come from the default
pool, so the thread running the window must be in the interactive one, or a
worker could take it over.
"""
threaded() = Threads.threadpool() == :interactive && Threads.nthreads(:default) > 0

Scan(dir::AbstractString) = begin
  dir = normpath(abspath(expanduser(dir)))
  length(dir) > 1 && (dir = rstrip(dir, '/'))
  st = stat(dir)
  isdir(st) || error("$dir isn't a folder")
  root = Item(dir, nothing, true, used(st))
  disks = Set{UInt64}([st.device])
  # On macOS the system and your files are on two volumes that look like one
  dir == "/" && isdir("/System/Volumes/Data") && push!(disks, stat("/System/Volumes/Data").device)
  closed = Channel{Tuple{Item,Int,String}}(0)
  close(closed)
  s = Scan(root, closed, Channel{Listing}(Inf), Tuple{Item,Int,String}[], 0,
           Dict{Tuple{UInt64,UInt64},Item}(), disks, time(), 0.0, 0)
  ask!(s, root)
  s
end

running(s::Scan) = s.finished == 0
elapsed(s::Scan) = (running(s) ? time() : s.finished) - s.started

"Send `folder` to be listed, starting workers if none are running"
ask!(s::Scan, folder::Item) = begin
  folder.asked += 1
  job = (folder, folder.asked, path(folder))
  s.waiting += 1
  threaded() || return push!(s.queue, job)
  if !isopen(s.jobs)
    s.jobs = Channel{Tuple{Item,Int,String}}(Inf)
    for _ in 1:Threads.nthreads(:default)
      Threads.@spawn :default work(s.jobs, s.done)
    end
  end
  put!(s.jobs, job)
end

"Stop the workers. They finish the folder they're listing first."
stop!(s::Scan) = close(s.jobs)

"Add what the workers have found to the tree, for up to `seconds`"
step!(s::Scan, seconds) = begin
  stop = time() + seconds
  while time() < stop
    if isready(s.done)
      add!(s, take!(s.done))
    elseif !isempty(s.queue)
      add!(s, list(popfirst!(s.queue)...))
    else
      break
    end
  end
  if running(s) && s.waiting == 0
    s.finished = time()
    stop!(s)
  end
  s
end

"Add a folder's contents to the tree, and ask for the folders in it to be listed"
add!(s::Scan, l::Listing) = begin
  s.waiting -= 1
  folder = l.folder
  # Skip it if the folder has been rescanned since it was asked for
  (l.asked == folder.asked && within(folder, s.root)) || return
  folder.read = true
  if l.denied
    folder.denied = true
    s.denied += 1
    return
  end
  dir = path(folder)
  bytes, files = 0, 0
  for e in l.entries
    if e.folder
      (e.device in s.disks && !(joinpath(dir, e.name) in SKIP)) || continue
      child = Item(e.name, folder, true, e.bytes)
      ask!(s, child)
    else
      child = Item(e.name, folder, false, e.bytes)
      if e.links > 1
        key = (e.device, e.inode)
        counted = get(s.seen, key, nothing)
        # It's counted again if what counted it has been rescanned since
        counted !== nothing && within(counted, s.root) ? (child.bytes = 0) : (s.seen[key] = child)
      end
      files += 1
    end
    push!(folder.children, child)
    bytes += child.bytes
  end
  add!(folder, bytes, files)
end

"Add space and files to `item` and every folder above it"
add!(item, bytes, files) = begin
  while item !== nothing
    item.bytes += bytes
    item.files += files
    item.sorted = false
    item = item.parent
  end
end

"Forget what's in `folder` and read it again"
rescan!(s::Scan, folder::Item) = begin
  folder.folder || return s
  for child in folder.children
    child.parent = nothing
  end
  st = try stat(path(folder)) catch; nothing end
  own = st === nothing ? 0 : used(st)
  add!(folder.parent, own - folder.bytes, -folder.files)
  folder.bytes, folder.files = own, 0
  folder.children = Item[]
  folder.read = folder.denied = false
  folder.sorted = true
  running(s) || (s.started = time())
  s.finished = 0.0
  ask!(s, folder)
  s
end

export Item, Scan, step!, stop!, running, elapsed, sorted, lineage, within, rescan!, path
