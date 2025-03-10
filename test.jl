@use "github.com/jkroso/Units.jl" Length mm cm m ["Typography" pt px] ["Imperial" inch]
@use "github.com/jkroso/Rutherford.jl/test.jl" @test testset
@use "github.com/jkroso/Sequences.jl/collections/Map.jl" Map assoc
@use "./style" @style_str Style Border parse_value BorderStyle BorderSide black Radius split_args Width Height TextConfig Font
@use Colors: Colorant

testset("split_args") do
  @test split_args(raw"a b c") == ["a", "b", "c"]
  @test split_args(raw"a $1 c") == ["a", 1, "c"]
  @test split_args(raw"a $1") == ["a", 1]
  @test split_args(raw"$1") == [1]
  @test split_args(raw"$(1 + 2)") == [:(1+2)]
  @test split_args(raw"$(1 + 2) b") == [:(1+2), "b"]
  @test split_args(raw"a $(1 + 2) b") == ["a", :(1+2), "b"]
end

const white = parse(Colorant, "#fff")
const red = parse(Colorant, "red")

testset("parse_value") do
  @test parse_value(BorderSide, Val(1), "1px") == 1px
  @test parse_value(BorderSide, Val(2), "solid") == BorderStyle.solid
  @test parse_value(BorderSide, Val(3), "#fff") == white
end

@test style"border: 1px solid #fff" == Style(:border=>Border(BorderSide(1px, BorderStyle.solid, white)))
@test style"border[top]: 1px solid #fff" == Style(:border=>Border(top=BorderSide(1px, BorderStyle.solid, white)))
@test style"border.color: #fff" == Style(:border=>Border(BorderSide(0mm, BorderStyle.none, white)))
@test style"border.width: 3mm" == Style(:border=>Border(BorderSide(3mm, BorderStyle.none, black)))
@test style"border[top].width: 3mm" == Style(:border=>Border(top=BorderSide(3mm, BorderStyle.none, black)))
@test style"radius: 3mm" == Style(:radius=>Radius(3mm))
@test style"radius: 3mm 2mm" == Style(:radius=>Radius(3mm, 2mm))
@test style"radius[tr]: 3mm" == Style(:radius=>Radius(tr=3mm))
@test style"radius[tr,br]: 3mm" == Style(:radius=>Radius(tr=3mm,br=3mm))
@test style"radius.tr: $(3mm+1mm)" == Style(:radius=>Radius(tr=4mm))
@test style"radius.tr: $(true ? 2mm : 3mm)" == Style(:radius=>Radius(tr=2mm))
@test style"border.width: $(3mm)" == Style(:border=>Border(BorderSide(3mm, BorderStyle.none, black)))
@test style"width: 20mm 50mm 30mm" == Style(:width=>Width(20mm, 50mm, 30mm))
@test style"width.max: 50mm" == Style(:width=>Width(max=50mm))
@test style"text: 7mm red Helvetica" == Style(:text=>TextConfig(size=7mm, color=red, font=Font("Helvetica")))
@test style"text.color: red" == Style(:text=>TextConfig(color=red))
