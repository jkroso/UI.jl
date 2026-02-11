@use "github.com/jkroso/Prospects.jl" @mutable @abstract @struct Field assoc group interleave
@use "github.com/jkroso/Rutherford.jl" doodle ["draw" hstack vstack brief]
@use "github.com/jkroso/Promises.jl" @defer
@use "github.com/jkroso/DOM.jl" => DOM @dom @css_str
@use "../types.jl" UINode Component TextNode @ui tree dom
@use "../event.jl" onmousedown
@use "./basic.jl" describe expand
@use Atom: EvalError

dom(t::TextNode) = DOM.Text(t.value)

@use "./Symbol.jl" SymbolUI
describe(d::Symbol, key) = SymbolUI(key=key)
@use "./String.jl" StringUI
describe(d::AbstractString, key) = StringUI(key=key)
@use "./Number.jl" NumberUI
describe(d::Number, key) = NumberUI(key=key)
@use "./Pair.jl" PairUI
describe(d::Pair, key) = PairUI(key=key)
@use "./Tuple.jl" TupleUI NamedTupleUI
describe(d::Tuple, key) = TupleUI(key=key)
describe(d::NamedTuple, key) = NamedTupleUI(key=key)
@use "./Dict.jl" DictUI
describe(d::AbstractDict, key) = DictUI(key=key)
@use "./Error.jl" ErrorUI
describe(d::EvalError, key) = ErrorUI(key=key)
# @use "./KeyCombo.jl" KeyComboUI
# describe(kc::KeyCombo, key) = @ui[KeyComboUI key=key]

# TODO: delete this
describe(ui::UINode) = ui
