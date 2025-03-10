@use "github.com/jkroso/Prospects.jl" @mutable Field
@use "github.com/jkroso/Units.jl" ms
@use "github.com/jkroso/DOM.jl" Node @css_str @dom
@use "../types.jl" UINode Component adopt @ui dom focus children
@use "../event.jl" onmousedown onkeydown ondblclick onfocusout onfocusin tick emit Change Submit
@use "./basic.jl" VStack chevron dom_attrs
@use "./TextInput.jl" TextInput

@mutable struct TypeChooser <: Component
  choice::Union{DataType,Nothing}=nothing
  isopen::Bool=false
  top::DataType=Any
end

children(ui::TypeChooser) = begin
  UINode[
    @ui[ChosenOption isnothing(ui.choice) ? string(ui.top) : string(ui.choice)],
    @ui[DropDown]
  ]
end

@mutable ChosenOption <: Component

@mutable struct DropDown <: Component
  interest::Union{UINode,Nothing}=nothing
end

@mutable OptionGroup(title::String, collapsed=true) <: Component
@mutable Option <: Component

children(ui::DropDown) = begin
  UINode[@ui[TextInput(radius=:medium, placeholder="Search Filter") style"padding: 2mm"],
         options(ui.parent).children...]
end

Base.getproperty(t::DropDown, ::Field{:interest}) = begin
  isdefined(t, :interest) ? getfield(t, :interest) : t.children[2].children[2]
end

options(ui::TypeChooser) = options(ui.top)
options(::Type{T}) where T = begin
  if isabstracttype(T)
    @ui[OptionGroup(title=name(T)) map(options, subtypes(T))...]
  else
    @ui[Option name(T)]
  end
end

name(T::DataType) = string(T.name.name)
name(T::UnionAll) = name(T.body)

onmousedown(ui::ChosenOption, event) = begin
  ui.parent.isopen = !ui.parent.isopen
end

dom(ui::TypeChooser) = begin
  @dom[:div{dom_attrs(ui)...} (ui.isopen ? ui.children : [ui.firstchild])...]
end

dom(ui::DropDown) = begin
  @dom[:div css"""
            display: flex
            flex-direction: column
            max-height: 30rem
            border: 1px solid #181a1f
            border-radius: 0.3rem
            overflow: scroll
            margin-top: 2px
            background: #2a2d35
            > :first-child
              padding: 0.75rem
              padding-bottom: 0
              > :first-child:not(.editing) { border-color: #181a1f }
              > :first-child {width: 100%}
            > :last-child
              margin: 0.75rem
              border: 1px solid #181a1f
            """
    [:div ui.firstchild]
    [:div ui.children[2:end]...]]
end

dom(ui::ChosenOption) = begin
  @dom[:div css"""
            border: 1px solid #181a1f
            border-radius: 3px
            padding: 0.4rem 0.6rem
            display: inline-flex
            align-items: center
            """
    ui.children...]
end

dom(ui::OptionGroup) = begin
  collapsed = ui.collapsed
  @dom[:div css"""
            display: flex
            flex-direction: column
            padding: 0.75rem
            background: #2a2d35
            &:not(:last-child)
              border-bottom: 1px solid #181a1f
            &:not(:last-child) .leaves
              border-left: 1px solid #181a1f
            """
    [:div css"display: flex" chevron(!collapsed) ui.title]
    [:div css"margin-left: 0.1rem; padding-left: 1rem" class="leaves"
      (collapsed ? [] : ui.children)...]]
end

dom(ui::Option) = begin
  @dom[:div css"""
            padding-left: 2.2rem
            border-bottom: 1px solid #181a1f
            background: #2a2d35
            padding: 0.75rem
            """ ui.children...]
end

@ui[VStack style"padding: 3mm 0mm" [TypeChooser(top=Number, isopen=true) style""]]
