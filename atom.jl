@use "github.com/jkroso/Prospects.jl" @mutable @abstract @struct Field assoc group interleave
@use "github.com/jkroso/Destructure.jl" @destruct
@use "github.com/jkroso/Promises.jl" need Future
@use "github.com/jkroso/JSON.jl/write.jl" json
@use "github.com/jkroso/Source.jl" source
@use "github.com/jkroso/DOM.jl" => DOM @dom
@use "github.com/jkroso/Units.jl" ns
@use "./event.jl" emit parse_event Tick tick FocusIn FocusOut Focus KeyboardEvent onsubmit
@use "./types.jl" UINode TextNode dom focus onmount init
@use "./gui/basic" brief
@use "./gui" gui expand
@use Atom
@use Juno

macro showerrors(expr)
  quote
    try
      $(esc(expr))
    catch e
      Base.printstyled("ERROR: "; color=:red, bold=true)
      Base.showerror(stdout, e, catch_backtrace())
    end
  end
end

Atom.handle("rutherford eval2") do blocks
  single = length(blocks) == 1
  Atom.with_logger(Atom.JunoProgressLogger()) do
    lines = Set([x["line"] for x in blocks])
    total = length(blocks) + count(d->!(d.snippet.line in lines), values(inline_displays))
    Juno.progress(name="eval") do progress_id
      for (i, data) in enumerate(blocks)
        @destruct {"text"=>text, "line"=>line, "path"=>path, "id"=>id} = data
        snippet = Snippet(text, line, path, id)
        inline = @showerrors InlineDisplay(snippet, single)
        inline_displays[id] = inline
        @showerrors @invokelatest display(inline)
        @info "eval" progress=i/total _id=progress_id
      end
    end
  end
end

Atom.handle("result done2") do id
  delete!(inline_displays, id)
end

@struct Snippet(text::String, line::Int32, path::String, id::Int32)

evaluate(s::Snippet) = begin
  lock(evallock) do
    Atom.withpath(s.path) do
      m = Kip.get_module(s.path, interactive=true)
      Atom.@errs include_string(m, s.text, s.path, s.line)
    end
  end
end

const evallock = ReentrantLock()
const loading_gear = @dom[:span class="loading icon icon-gear"]

mutable struct InlineDisplay
  snippet::Snippet
  single::Bool
  error::Bool
  data::Any
  view::DOM.Node
  ui::UINode
  focused::UINode
  InlineDisplay(snippet, single) = begin
    data = evaluate(snippet)
    d = new(snippet, single, data isa Atom.EvalError, data, loading_gear)
    d.ui = gui(data)
    d.focused = d.ui
    setfield!(d.ui, :parent, TopNode(d, d.ui))
    single && expand(d.ui)
    init(d.ui)
    d
  end
end

@mutable TopNode(display::InlineDisplay, ui::UINode) <: UINode
Base.getproperty(t::TopNode, ::Field{:data}) = t.display.data
Base.setproperty!(t::TopNode, ::Field{:data}, x) = t.display.data = x
onsubmit(ui::TopNode, event) = begin
  display = ui.display
  @destruct {line, id} = display.snippet
  src = source(ui.data)
  display.snippet = assoc(display.snippet, :text, src)
  msg("edit2", (src=src, line=line, id=id))
end

get_display(ui::UINode) = get_display(ui.parent)
get_display(ui::TopNode) = ui.display

focus(ui::UINode) = begin
  display = get_display(ui)
  emit(display.focused, FocusOut(display.focused))
  display.focused = ui
  emit(ui, FocusIn(ui))
end

blur(ui::UINode) = begin
  display = get_display(ui)
  if display.focused == ui
    emit(ui, FocusOut(ui))
  end
  display.focused = nothing
end

const inline_displays = Dict{Int32,InlineDisplay}()
const first_renders = Channel{UINode}(Inf)

Base.convert(::Type{DOM.Node}, ui::UINode) = begin
  ui.stale || return ui_dom[ui]
  html = dom(ui)
  setfield!(ui, :stale, false)
  id = str_id(ui)
  if !haskey(id_ui, id)
    put!(first_renders, ui)
    finalizer(uncache, ui)
    id_ui[id] = ui
  end
  if !haskey(html.attrs, :id)
    html = assoc(html, :attrs, assoc(html.attrs, :id, id))
    ui_dom[ui] = html
  end
  html
end

Base.convert(::Type{DOM.Node}, ui::TextNode) = dom(ui)

str_id(x) = string(objectid(x), base=62)
const ui_dom = WeakKeyDict{UINode,DOM.Node}()
const id_ui = Dict{String,UINode}()
uncache(x::UINode) = begin
  delete!(ui_dom, x)
  delete!(id_ui, str_id(x))
end

msg(x; kwargs...) = msg(x, kwargs)
msg(x::String, args...) = begin
  if Atom.isactive(Atom.sock)
    # TODO: remove buffering
    println(Atom.sock, json(Any[x, args...]))
    flush(Atom.sock)
  end
end

Atom.handle("reset module") do file
  delete!(Kip.modules, file)
  Kip.get_module(file, interactive=true)
  nothing
end

const KeyboardRelated = Union{KeyboardEvent,Focus}

Atom.handle("event2") do id, data
  if haskey(inline_displays, id)
    display = inline_displays[id]
    target = get(id_ui, get(data, "target", ""), display.ui)
    event = parse_event(data, target)
    if event isa KeyboardRelated
      target = display.focused
    end
    @showerrors emit(target, event)
  end
end

parse_event(T::Type{FocusIn}, e::AbstractDict, target::UINode) = FocusIn(target.parent.display.focused)
parse_event(T::Type{FocusOut}, e::AbstractDict, target::UINode) = FocusOut(target.parent.display.focused)

Base.display(d::InlineDisplay) = display(d, convert(DOM.Node, d.ui))
Base.display(d::InlineDisplay, view::DOM.Node) = begin
  patch = DOM.diff(d.view, view)
  d.view = view
  if !isnothing(patch)
    msg("patch2", (id=d.snippet.id, patch=patch, state=d.error ? :error : :ok))
  end
end

tick(inline::InlineDisplay, event::Tick) = tick(inline.ui, event)

brief(e::Atom.EvalError) = begin
  err = e.err
  @dom[:span repr(err)]
end

Base.getproperty(ui::UINode, ::Field{:dimensions}) = begin
  dims = Atom.@rpc dimensions(str_id(ui))
  (x=dims[1], y=dims[2], width=dims[3], height=dims[4])
end


const atom_connected = Atom.handlers["connected"]
const connected = Future{Bool}()
Atom.handle("connected") do
  atom_connected()
  put!(connected, true)
end

function update(tick_info)
  for inline in values(inline_displays)
    tick(inline, tick_info)
    display(inline)
  end
end

get_display(line) = begin
  for inline in values(inline_displays)
    inline.snippet.line == line && return inline
  end
end

get_display(str::String) = begin
  for inline in values(inline_displays)
    inline.snippet.text == str && return inline
  end
end

const loop = @async begin
  wait(connected)
  time = time_ns()ns
  css = need(DOM.css[])
  msg("stylechange2", css)
  while true
    sleep(1//60)
    new_time = time_ns()ns
    tick = Tick(new_time - time, new_time)
    time = new_time
    @invokelatest update(tick)
    if css != need(DOM.css[])
      css = need(DOM.css[])
      msg("stylechange2", css)
    end
    while !isempty(first_renders)
      @invokelatest onmount(take!(first_renders))
    end
  end
end

errormonitor(loop)

# Hacks to get completion working with Kip modules
# const complete = Atom.handlers["completions"]
# Atom.handle("completions") do data
#   mod = Kip.get_module(data["path"], interactive=true)
#   try
#     complete(assoc(data, "mod", mod))
#   catch end
# end
#
# const module_handler = Atom.handlers["module"]
# Atom.handle("module") do data
#   ret = module_handler(data)
#   ret.main != "Main" && return ret
#   path = get(data, "path", "")
#   mod = Kip.get_module(path, interactive=true)
#   assoc(ret, :main, string(mod))
# end
#
# const workspace_handler = Atom.handlers["workspace"]
# Atom.handle("workspace") do mod
#   file = Atom.@rpc currentfile()
#   m = Kip.get_module(file, interactive=true)
#   workspace_handler(string(m))
# end
#
# const ismodule = Atom.handlers["ismodule"]
# Atom.handle("ismodule") do mod
#   file = Atom.@rpc currentfile()
#   isfile(file) || ismodule(mod)
# end
#
# Atom.getmodule(m::Module) = m
# Atom.getmodule(s::AbstractString) = begin
#   s = replace(s, r"…$"=>"") # if the name is long it will be elided
#   if occursin('⭒', s)
#     for m in values(Kip.modules)
#       startswith(string(m), s) && return m
#     end
#   else
#     invoke(Atom.getmodule, Tuple{Any}, s)
#   end
# end
