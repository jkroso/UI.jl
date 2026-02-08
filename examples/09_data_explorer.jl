# Data Explorer
#
# The gui() function automatically generates appropriate UI for any Julia data type.
# This is the library's core feature: pass in data, get an interactive UI back.

@use "../gui/main.jl" gui
@use "../types.jl" @ui

# Numbers get an editable NumberUI
number_ui = gui(42)
println("gui(42) → ", typeof(number_ui))

# Strings get a StringUI with cursor and editing support
string_ui = gui("Hello, World!")
println("gui(\"Hello, World!\") → ", typeof(string_ui))

# Symbols get a SymbolUI
symbol_ui = gui(:example)
println("gui(:example) → ", typeof(symbol_ui))

# Pairs get a PairUI showing key → value
pair_ui = gui(:name => "Alice")
println("gui(:name => \"Alice\") → ", typeof(pair_ui))

# Tuples get a TupleUI with each element as a child
tuple_ui = gui((1, "two", :three))
println("gui((1, \"two\", :three)) → ", typeof(tuple_ui))

# NamedTuples get labeled fields
named_ui = gui((x=10, y=20, z=30))
println("gui((x=10, y=20, z=30)) → ", typeof(named_ui))

# Dicts get an expandable DictUI
dict_ui = gui(Dict(:name => "Alice", :age => 30, :active => true))
println("gui(Dict(...)) → ", typeof(dict_ui))

# The gui() function is extensible - add methods for your own types:
#
#   struct MyWidget
#     value::Int
#   end
#
#   @mutable MyWidgetUI <: Component
#   gui(d::MyWidget, key) = MyWidgetUI(key=key)
#   children(ui::MyWidgetUI) = UINode[TextNode("Widget: $(ui.data.value)")]
