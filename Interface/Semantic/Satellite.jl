@use "github.com/jkroso/Prospects.jl" @def @abstract
@use "github.com/jkroso/Font.jl" ["units" px]
@use "../abstract" SemanticUI

"Computes the position of a floating element relative to a target"
satellite_position(placement::Symbol, gap::px,
                   target_x::px, target_y::px, target_w::px, target_h::px,
                   sat_w::px, sat_h::px) = begin
  if placement == :bottom
    x = target_x + target_w/2 - sat_w/2
    y = target_y + target_h + gap
  elseif placement == :top
    x = target_x + target_w/2 - sat_w/2
    y = target_y - sat_h - gap
  elseif placement == :right
    x = target_x + target_w + gap
    y = target_y + target_h/2 - sat_h/2
  elseif placement == :left
    x = target_x - sat_w - gap
    y = target_y + target_h/2 - sat_h/2
  else
    error("unknown placement: $placement")
  end
  (x, y)
end

@abstract struct AbstractSatellite <: SemanticUI
  placement::Symbol = :bottom
  gap::px = 4px
end

export AbstractSatellite, satellite_position
