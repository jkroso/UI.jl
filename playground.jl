:a
1

Dict(:a=>1,:b=>2,:c=>3)
Dict(:a=>Dict('b'=>Dict()))
(a=1,b=Dict(:c=>4))
(1,Dict(:a=>1))
Set([1,2,3])

length

struct A
  a::Rational
  b
end
A(1,Dict(:a=>3))
3+2//11
error("a")

using Markdown

md"""
  # a
  ```julia
  1 + 2
  ```
  ## b
  ```clojure
  (+ 1 2)
  ```
  ### c
  ```coffee
  1 + 2
  ```
  #### d
  _________________

  _a_b__C__
  ```
  1 + 2
  ```
  - [ ] a
  - [x] b
  """

quote
  a + b
  1+2
  a(b) = 'c'
  const a = "$a $(1)"
  quote
    $(1+2)
    $a end
  (1,3,4)
  (a=2,)
  a->a
end

19023120
1902.3423

"10000"[1:2]
5:-3:1|>reverse
0:3:5

@use "github.com/jkroso/Rutherford.jl" doodle draw @dom @css_str Edit [
  "draw.jl" hstack vstack brief body]
@use "github.com/rofinn/FilePathsBase.jl" PosixPath @p_str exists

doodle(p::PosixPath) = exists(p) ? transform(p) : @dom[:span repr(p)]
extension(path) = Symbol(isdir(path) ? "/" : splitext(path)[end][2:end])

"Render file directory"
transform(dir, ::Val{:/}) = begin
  @dom[:div css"""
          display: flex
          flex-direction: column
          margin: 10px auto
          width: max-content
          border: 1px solid lightgrey
          border-radius: 3px
          > a {padding: 3px 10px; font-size: 1.2em; border-bottom: 1px solid lightgrey}
          > a:last-child {border-bottom: none}
          """
      (@dom[:a href=string(joinpath(dir, name)) name] for name in readdir(dir))...]
end

transform(path, mime=Val(extension(path))) = begin
  html = read(`pygmentize -f html -O "noclasses" $(string(path))`, String)
  @dom[:div css"""
            margin: 10px auto
            max-width: 800px
            > div.highlight > pre {font: 1em SourceCodePro-light}
            """ parse(MIME("text/html"), html)]
end

p"./Readme.md"
p"."

@use "github.com/jkroso/Rutherford.jl/test.jl" @test testset
@test [1,2,4,6,9] == [1,2,4,6,9]
testset("a test") do
  @test true
end

@use "github.com/jkroso/Rutherford.jl" @dom @css_str Edit @component focus [
  "draw.jl" draw hstack vstack brief DictKey DictValue]

@component DictEditor(state=(isadding=false,))
draw(::Edit, ctx, d::Dict) = DictEditor() do c
  items = [@dom[hstack
                 [DictKey key=i onmousedown=focus]
                 [:span css"padding: 0 10px" "→"]
                 [DictValue key=key onmousedown=focus]] for (i, key) in enumerate(keys(d))]
  @dom[vstack
    brief(d)
    [vstack css"padding-left: 1em" items...]]
end

Dict("a"=>1)

Vector
Vector{Int}
Matrix
DenseArray
Rational
