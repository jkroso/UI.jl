@use "github.com/jkroso/Units.jl" mm ["Typography" pt]
@use "github.com/jkroso/Prospects.jl" @mutable assoc
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom children
@use "../event.jl" onmousedown
@use "./basic.jl" VStack Expandable expansion describe brief
@use "../selector.jl" KeyKey
@use "./Symbol.jl" SymbolUI
@use "./Table.jl" Table Row Body Cell

@mutable TupleUI <: Expandable

expansion(t::Tuple) = begin
  @ui[Table(index=true) class=css"""
                              background: white
                              tbody > tr > :is(td,th) {padding: 0.4rem 0.9rem}
                              tbody > tr > th:first-child
                                font: 1.3rem lighter, var(--editor-font-family)
                              """
    (@ui[Row class=css"""
                   &:not(:last-child) {border-bottom: 1px solid #e5e7eb}
                   th {border-right: 1px solid #e5e7eb; text-align: right}
                   """ describe(x, i)] for (i, x) in enumerate(t))...]
end

@mutable NamedTupleUI <: Expandable
@mutable FieldUI <: Component

expansion(t::NamedTuple) = begin
  types = typeof(t).parameters[2].parameters
  @ui[Table class=css"""
                  tbody > tr > :is(td,th) {padding: 0.4rem 0.9rem}
                  tbody > tr > th:first-child
                    font: 1.3rem lighter, var(--editor-font-family)
                  background: white
                  """
    (@ui[Row class=css"""
                    :is(td,th):not(:last-child) {border-right: 1px solid #e5e7eb}
                    &:not(:last-child) {border-bottom: 1px solid #e5e7eb}
                    """
        FieldUI(key=i)
        describe(v, i)] for (i,v) in enumerate(t))...]
end

dom(ui::FieldUI) = begin
  nt = ui.parent.data
  (fields, types) = typeof(nt).parameters
  @dom[:span fields[ui.key]
             [:span class="syntax--keyword syntax--operator syntax--relation syntax--types" "::"]
             brief(types.parameters[ui.key])]
end

brief(data::NamedTuple) = begin
  @dom[:span class="syntax--support syntax--type"
    "NamedTuple" [:span css"color: rgb(104, 110, 122)" "[$(length(data))]"]]
end

# (1, :b, "c", (a = 1, b = 2))
# (a = 1, b = :b, cd = "d", d = 9, f = 1, g = (a = 1, b = 2))
