# A sheet is a list of rows that work things out, like the one in Centient's
# notepad. Each row has a name and a Julia expression, and the expression can
# use the names of the rows above it the way they're written: "Wall length * 2".
# In a document it's a code block in the language `sheet`, one row to a line:
#
#     ```sheet
#     Wall length = 12m
#     Wall height = 2.4m
#     Area = wall length * wall height
#     ```
#
# This file reads a row, finds the names in an expression and works out the
# value of every row. Numbers can have units, from Units.jl: 12m, 25mm, 2hr.
# Columns count characters from 0, as they do in markdown.jl.

@use "github.com/jkroso/Units.jl" => Units
@use "github.com/jkroso/Units.jl/Imperial" => Imperial
@use "./markdown" Cell

"The language of a code block that is a sheet"
const SHEET = "sheet"

const NOT_A_NAME = "()[]{}\"'`+*/^<>!|&,;=\\"

"The index of the = that ends the name of a row, or 0 when the row has no name"
separator(chars) = begin
  q = findfirst(==('='), chars)
  q === nothing && return 0
  q < length(chars) && chars[q+1] == '=' && return 0
  any(c -> c in NOT_A_NAME, chars[1:q-1]) ? 0 : q
end

"The text of `chars[from:to]` as a cell, without the spaces around it. The caret can go as far as `limit`."
cell(chars, from, to, limit) = begin
  a = findnext(!isspace, chars, from)
  (a === nothing || a > to) && return nothing
  z = findprev(!isspace, chars, to)
  Cell(a - 1, z, max(z, limit))
end

"""
The cells of one row of a sheet: its name and its expression, or only its
expression when the row has no name. A row like ` = 2 + 2` has a name that is
empty.
"""
sheetcells(text::AbstractString) = begin
  chars = collect(text)
  n = length(chars)
  q = separator(chars)
  if q == 0
    return [something(cell(chars, 1, n, n), Cell(0, 0, n))]
  end
  # One space before the = is left alone, and one after it
  name = something(cell(chars, 1, q - 1, q - 2), Cell(0, 0, max(0, q - 2)))
  lo = min(q + 1, n)
  [name, something(cell(chars, q + 1, n, n), Cell(lo, lo, n))]
end

"The name and the expression of a row, as text"
parts(text::AbstractString) = begin
  chars = collect(text)
  cs = sheetcells(text)
  get(c) = String(chars[c.lo+1:c.hi])
  length(cs) == 1 ? ("", get(cs[1])) : (get(cs[1]), get(cs[2]))
end

"The name Julia knows a row by: \"Wall length\" is wall_length. It's empty when the row's name has no letters or digits."
ident(name::AbstractString) = begin
  s = strip(replace(lowercase(strip(name)), r"[^a-z0-9]+" => "_"), '_')
  isempty(s) ? "" : isdigit(first(s)) ? "_" * s : String(s)
end

isname(c::Char) = isletter(c) || isdigit(c) || c == '_'

"True for each character of `chars` that is code, not part of a string or a comment"
code(chars) = begin
  out = trues(length(chars))
  i = 1
  while i <= length(chars)
    c = chars[i]
    if c == '#'
      out[i:end] .= false
      break
    elseif c == '"'
      j = i + 1
      while j <= length(chars) && chars[j] != '"'
        j += chars[j] == '\\' ? 2 : 1
      end
      out[i:min(j, end)] .= false
      i = j
    end
    i += 1
  end
  out
end

"True when a name can start at `chars[i]`: after something that isn't part of a name, or after a number as in 2area"
starts(chars, i) = begin
  i == 1 && return true
  c = chars[i-1]
  # After a dot it's a field of a value, unless the dot ends a number
  c == '.' && return i > 2 && isdigit(chars[i-2])
  isname(c) || return true
  isdigit(c) || return false
  k = i - 1
  while k > 1 && (isdigit(chars[k-1]) || chars[k-1] == '.'); k -= 1 end
  k == 1 || !isname(chars[k-1])
end

"""
Where `text` uses one of `names`, as (lo, hi, name) with the columns the name
runs from and to. A name counts whatever its capitals are, and only as whole
words outside a string or a comment. The longest name wins, so "wall" doesn't
take the start of "wall length".
"""
uses(text::AbstractString, names) = begin
  chars = collect(text)
  low = map(lowercase, chars)
  free = code(chars)
  out = Tuple{Int,Int,String}[]
  for name in sort(collect(names), by=length, rev=true)
    want = map(lowercase, collect(strip(name)))
    n = length(want)
    n == 0 && continue
    for i in 1:length(chars)-n+1
      (low[i:i+n-1] == want && all(free[i:i+n-1]) && starts(chars, i)) || continue
      i + n <= length(chars) && isname(chars[i+n]) && continue
      free[i:i+n-1] .= false
      push!(out, (i - 1, i + n - 1, String(name)))
    end
  end
  sort!(out)
end

"`text` with each of `names` written as Julia knows it"
rewrite(text::AbstractString, names) = begin
  chars = collect(text)
  out = IOBuffer()
  at = 0
  for (lo, hi, name) in uses(text, names)
    print(out, String(chars[at+1:lo]), ident(name))
    at = hi
  end
  print(out, String(chars[at+1:end]))
  String(take!(out))
end

"What a row came to. `text` is its value as the row shows it, or what went wrong."
struct Result
  text::String
  failed::Bool
end

const NONE = Result("", false)

"Every name of `mod` that a sheet can use"
bindings(mod::Module) = begin
  out = Dict{Symbol,Any}()
  for n in names(mod; all=true)
    s = string(n)
    (n === nameof(mod) || n === :eval || startswith(s, "#") || startswith(s, "include") || !isdefined(mod, n)) && continue
    out[n] = getfield(mod, n)
  end
  out
end

const prelude = Ref{Any}(nothing)

"A module that holds the units, for every sheet to use"
units() = begin
  prelude[] === nothing || return prelude[]
  mod = Module(:SheetUnits)
  all = merge(bindings(Units), bindings(Imperial))
  Core.eval(mod, Expr(:block, [Expr(:const, Expr(:(=), n, QuoteNode(v))) for (n, v) in all]...))
  Core.eval(mod, Expr(:export, keys(all)...))
  prelude[] = mod
end

commas(s::AbstractString) = replace(s, r"(?<=\d)(?=(\d{3})+$)" => ",")

"A number the way a person writes it: 54 not 54.0, and 14,285.7 not 14285.714285714286"
shown(x::Integer) = commas(string(x))
shown(x::Bool) = string(x)
shown(x::Rational) = isone(denominator(x)) ? shown(numerator(x)) : shown(float(x))
shown(x::AbstractFloat) = begin
  isfinite(x) || return string(x)
  isinteger(x) && abs(x) < 1e15 && return shown(round(Int, x))
  (abs(x) >= 1e15 || abs(x) < 1e-4) && return string(round(x, sigdigits=6))
  # Big numbers keep fewer places after the point
  places = abs(x) >= 100 ? 2 : abs(x) >= 1 ? 4 : 6
  s = rstrip(rstrip(Base.Ryu.writefixed(Float64(x), places), '0'), '.')
  whole, part = occursin('.', s) ? split(s, '.') : (s, "")
  isempty(part) ? commas(whole) : commas(whole) * "." * part
end
shown(x::AbstractString) = repr(x)
shown(::Nothing) = ""
shown(f::Function) = "ƒ"
shown(x) = begin
  s = sprint(show, x)
  # A number with a unit, like 28.799999999999997m², shows its number the same way
  m = match(r"^(-?[\d,]*\.?\d+(?:e[+-]?\d+)?)(\D.*)$", s)
  n = m === nothing ? nothing : tryparse(Float64, replace(m[1], "," => ""))
  n === nothing ? s : shown(n) * m[2]
end

const LONGEST = 48   # characters of a value or an error that a row shows

brief(s::AbstractString) = begin
  s = replace(first(split(s, '\n')), r"\s+" => " ")
  length(s) > LONGEST ? first(s, LONGEST - 1) * "…" : String(s)
end

"What went wrong, in a few words"
problem(err) = begin
  err isa UndefVarError && return "$(err.var) isn't a name here"
  err isa Meta.ParseError && return "This isn't finished"
  brief(sprint(showerror, err))
end

"""
Work out every row of a sheet, from the top. `rows` holds the name and the
expression of each one. A row that goes wrong says so, and the rows after it
carry on.
"""
tally(rows) = begin
  mod = Module(:Sheet)
  Core.eval(mod, Expr(:block, Expr(:const, Expr(:(=), :SheetUnits, units())), Expr(:using, Expr(:., :., :SheetUnits))))
  names = String[]
  map(rows) do (name, expr)
    isempty(strip(expr)) && return NONE
    try
      ex = Meta.parse(rewrite(expr, names))
      ex isa Expr && ex.head in (:incomplete, :error) && return Result("This isn't finished", true)
      value = Core.eval(mod, ex)
      id = ident(name)
      if !isempty(id)
        Core.eval(mod, Expr(:(=), Symbol(id), QuoteNode(value)))
        filter!(n -> ident(n) != id, names)
        push!(names, String(strip(name)))
      end
      Result(brief(Base.invokelatest(shown, value)), false)
    catch err
      Result(problem(err), true)
    end
  end
end

"The names that the expression of row `r` can use: those of the rows above it"
known(rows, r::Int) = unique(String[strip(name) for (name, _) in rows[1:r-1] if !isempty(ident(name))])

export SHEET, Result, sheetcells, parts, ident, uses, tally, known
