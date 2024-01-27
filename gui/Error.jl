@use "github.com/jkroso/Prospects.jl" @mutable assoc
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component @ui dom children
@use "../event.jl" onmousedown
@use "./basic.jl" Expandable expansion brief
@use Atom

@mutable ErrorUI <: Expandable

expansion(ui::Atom.EvalError) = @ui[StackTraceUI(key=:trace)]

@mutable StackTraceUI <: Component

children(ui::StackTraceUI) = reverse!(UINode[StackFrameUI(key=i) for i in eachindex(ui.data[1:end-23])])
dom(ui::StackTraceUI) = @dom[:div class="error-trace" ui.children...]

@mutable StackFrameUI <: Component
children(ui::StackFrameUI) = begin
  UINode[@ui[StackLink(file=ui.data.file, line=ui.data.line)]]
end

dom(ui::StackFrameUI) = begin
  frame = ui.data
  @dom[:div class="trace-entry $(Atom.locationshading(string(frame.file))[2:end])"
    fade("in ")
    brief(frame)
    fade(" at ")
    ui.firstchild
    fade(frame.inlined ? " <inlined>" : "")]
end

@mutable StackLink(file, line) <: Component
dom(ui::StackLink) = stacklink(string(ui.file), ui.line)

onmousedown(ui::StackLink, event) = begin
  Atom.@msg openFile(ui.file, ui.line-1)
end

fade(s) = @dom[:span class="fade" s]

expandpath(path) = begin
  isempty(path) && return (path, path)
  Atom.isuntitled(path) && return ("untitled", path)
  !isabspath(path) && return (normpath(joinpath("base", path)), Atom.basepath(path))
  ("./" * relpath(path, homedir()), path)
end

stacklink(::Nothing, line) = fade("<unknown file>")
stacklink(path, line) = begin
  path == "none" && return fade("$path:$line")
  path == "./missing" && return fade("./missing")
  name, path = expandpath(path)
  @dom[:a Atom.appendline(name, line)]
end

brief(f::StackTraces.StackFrame) = begin
  f.linfo isa Nothing && return @dom[:span string(f.func)]
  f.linfo isa Core.CodeInfo && return @dom[:span repr(f.linfo.code[1])]
  f.linfo isa Module && return @dom[:span repr(f.linfo) '.' replace(repr(f), r"^([^\s]+).+$"=>s"\1")]
  @dom[:span replace(sprint(Base.show_tuple_as_call, f.linfo.def.name, f.linfo.specTypes),
                     r"^([^(]+)\(.*\)$"=>s"\1")]
end
