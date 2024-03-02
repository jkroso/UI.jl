@use "github.com/jkroso/Prospects.jl" @mutable @abstract @struct Field assoc group interleave
@use "github.com/jkroso/Rutherford.jl" doodle ["draw" hstack vstack brief]
@use "github.com/jkroso/Promises.jl" @defer
@use "github.com/jkroso/DOM.jl" => DOM @dom @css_str
@use "../types.jl" UINode Component TextNode @ui tree dom
@use "../event.jl" onmousedown KeyCombo
@use "./basic.jl" gui expand
@use Atom

dom(t::TextNode) = DOM.Text(t.value)

@use "./Symbol.jl" SymbolUI
gui(d::Symbol, key) = SymbolUI(key=key)
@use "./String.jl" StringUI
gui(d::AbstractString, key) = StringUI(key=key)
@use "./Number.jl" NumberUI
gui(d::Number, key) = NumberUI(key=key)
@use "./Pair.jl" PairUI
gui(d::Pair, key) = PairUI(key=key)
@use "./Tuple.jl" TupleUI NamedTupleUI
gui(d::Tuple, key) = TupleUI(key=key)
gui(d::NamedTuple, key) = NamedTupleUI(key=key)
@use "./Error.jl" ErrorUI
gui(d::Atom.EvalError, key) = ErrorUI(key=key)
@use "./KeyCombo.jl" KeyComboUI
gui(kc::KeyCombo, key) = @ui[KeyComboUI key=key]

# TODO: delete this
gui(ui::UINode) = ui
