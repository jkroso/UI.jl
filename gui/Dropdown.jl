@use "github.com/jkroso/Prospects.jl" @mutable @field_str Field @abstract
@use "github.com/jkroso/DOM.jl" @css_str @dom Map
@use "../types.jl" UINode Component dom
@use "../event.jl" onmousedown left
@use "./Satellite.jl" AbstractSatellite position
@use "github.com/jkroso/Units.jl" mm

@abstract struct AbstractDropdown <: AbstractSatellite end

onmousedown(ui::AbstractDropdown, event) = begin
  event.button == left || return nothing
  if event.target === ui.firstchild || event.target in ui.firstchild
    ui.show = !ui.show
  end
end

@mutable Dropdown <: AbstractDropdown

@use "./basic" HStack @ui
@ui[HStack style"padding: 40mm; padding[top,bottom]: 20mm"
  [Dropdown(show=true, placement=:bottom)
    [HStack style"padding: 1mm 2mm; border: 0.2mm; radius: 1mm" "target"]
    [HStack style"padding: 1mm 2mm; border: 0.2mm; radius: 1mm" "Satellite"]]]
