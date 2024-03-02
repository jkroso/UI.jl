@use "github.com/jkroso/Prospects.jl" @mutable
@use "github.com/jkroso/DOM.jl" @css_str @dom
@use "../types.jl" UINode Component @ui dom children
@use "../event.jl" KeyCombo @key_str
@use "./basic.jl" HStack
@use "./Icon.jl" Icon

const modicon = (cmd=Icon("command"),
                 opt=Icon("option"),
                 ctrl=Icon("chevron-up"),
                 shft=Icon("shift"),
                 ArrowDown=Icon("arrow-down"),
                 ArrowUp=Icon("arrow-up"),
                 ArrowLeft=Icon("arrow-left"),
                 ArrowRight=Icon("arrow-right"),
                 Delete=Icon("backspace-reverse"))

@mutable KeyComboUI <: Component
@mutable KeyUI <: Component

children(ui::KeyComboUI) = begin
  c = ui.data
  [(@ui[KeyUI get(modicon, mod)] for mod in c.mods)...,
    @ui[KeyUI get(modicon, c.key, @ui[HStack String(c.key)])]]
end

dom(ui::KeyComboUI) = begin
  @dom[:div css"display: flex" ui.children...]
end

dom(ui::KeyUI) = begin
  @dom[:div css"""
            display: flex
            padding: 0.2rem
            justify-content: center
            align-items: center
            margin: 0 0.3rem
            border-radius: 0.2rem
            box-shadow: 0 0 2px 0px lightgray
            min-width: 1.7rem
            height: 1.7rem
            > div
              font-size: 1.4rem
              height: 0
            """
    ui.children...]
end

key"ArrowDown"
key"ArrowDown+ctrl+opt+shft"
key"ArrowUp+cmd+ctrl"
key"ArrowLeft+ctrl+opt+shft"
key"ArrowRight+ctrl+opt+shft"
key"Delete+ctrl+opt+shft"
key"a+cmd"
