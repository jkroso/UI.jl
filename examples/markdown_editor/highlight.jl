# Splits a line of code into the parts a code block draws in different colours:
# comments, strings, numbers, keywords, the names of functions being called and
# the names of types. It reads one line at a time and knows a little about each
# language, so it's quick, and it's wrong about things that run over several
# lines, like a string in triple quotes.

"What a language's code looks like"
struct Language
  keywords::Set{String}
  literals::Set{String}      # words like true and nothing
  comment::String            # what starts a comment that runs to the end of the line
  quotes::String             # the characters that open and close a string
  chars::Bool                # true when 'x' is one character, not a string
  bang::Bool                 # true when a name can end in !
end

Language(keywords, literals; comment="//", quotes="\"'", chars=false, bang=false) =
  Language(Set(split(keywords)), Set(split(literals)), comment, quotes, chars, bang)

const JULIA = Language("""abstract baremodule begin break catch const continue do else elseif end export finally for
                          function global if import in isa let local macro module mutable primitive quote return
                          struct try type using where while""",
                       "true false nothing missing Inf NaN pi", comment="#", quotes="\"`", chars=true, bang=true)

const PYTHON = Language("""and as assert async await break class continue def del elif else except finally for from
                           global if import in is lambda nonlocal not or pass raise return try while with yield""",
                        "True False None self", comment="#")

const JAVASCRIPT = Language("""as async await break case catch class const continue default delete do else enum export
                               extends finally for from function if implements import in instanceof interface let new
                               of return static switch throw try type typeof var void while yield""",
                            "true false null undefined this super NaN Infinity", quotes="\"'`")

const RUST = Language("""as async await break const continue crate dyn else enum extern fn for if impl in let loop match
                         mod move mut pub ref return static struct trait type unsafe use where while""",
                      "true false self Self None Some Ok Err", quotes="\"", chars=true, bang=true)

const C = Language("""auto break case catch class const continue default defer delete do else enum extern final for
                      func go goto if import inline interface map namespace new package private protected public
                      range return sizeof static struct switch template throw try typedef union using var virtual
                      void volatile while""",
                   "true false null nil nullptr NULL this self", chars=true)

const SHELL = Language("case do done elif else esac export fi for function if in local return then until while",
                       "true false", comment="#")

const SQL = Language("""select from where and or not null insert into values update set delete create table drop alter
                        add join left right inner outer on as group by order having limit distinct union index
                        primary key references default is in like between exists""",
                     "true false", comment="--", quotes="'\"")

const DATA = Language("", "true false null yes no", comment="#")

const LANGUAGES = Dict{String,Language}()
for (names, language) in ("julia jl ui" => JULIA, "python py" => PYTHON,
                          "javascript js jsx typescript ts tsx" => JAVASCRIPT, "rust rs" => RUST,
                          "c cpp c++ h go java swift kotlin csharp cs zig" => C,
                          "bash sh zsh shell fish" => SHELL, "sql" => SQL, "json yaml yml toml" => DATA)
  for name in split(names)
    LANGUAGES[name] = language
  end
end

"One part of a line of code. `kind` is :plain, :comment, :string, :number, :keyword, :call or :type."
struct Token
  col::Int       # the column of its first character
  text::String
  kind::Symbol
end

isname(c::Char) = isletter(c) || isdigit(c) || c == '_'

"Where the string that opens at `chars[i]` closes. An unclosed string runs to the end of the line."
closing(chars, i) = begin
  j = i + 1
  while j <= length(chars)
    chars[j] == '\\' && (j += 2; continue)
    chars[j] == chars[i] && return j
    j += 1
  end
  length(chars)
end

const NUMBER = r"^(0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*(\.\d+)?([eE][+-]?\d+)?)"

"The parts of one line of code written in the language named `name`"
tokens(text::AbstractString, name::AbstractString) = begin
  lang = get(LANGUAGES, lowercase(name), nothing)
  lang === nothing && return [Token(0, String(text), :plain)]
  chars = collect(text)
  n = length(chars)
  out = Token[]
  plain = 1
  # Add chars[i:j] as one token, after whatever plain text came before it
  add(i, j, kind) = begin
    plain < i && push!(out, Token(plain - 1, String(chars[plain:i-1]), :plain))
    push!(out, Token(i - 1, String(chars[i:j]), kind))
    plain = j + 1
  end
  starts(s, i) = !isempty(s) && i + length(s) - 1 <= n && all(chars[i+k-1] == c for (k, c) in enumerate(s))
  i = 1
  while i <= n
    c = chars[i]
    if starts(lang.comment, i)
      add(i, n, :comment)
      break
    elseif c in lang.quotes
      j = closing(chars, i)
      add(i, j, :string)
      i = j + 1
    elseif c == '\'' && lang.chars
      # 'x' and '\n' are characters. A lone ' is something else, like a transpose.
      j = i + 2 <= n && chars[i+1] != '\\' && chars[i+2] == '\'' ? i + 2 :
          i + 3 <= n && chars[i+1] == '\\' && chars[i+3] == '\'' ? i + 3 : 0
      j == 0 || add(i, j, :string)
      i = max(i, j) + 1
    elseif isdigit(c) && (i == 1 || !isname(chars[i-1]))
      j = i + length(match(NUMBER, String(chars[i:end])).match) - 1
      add(i, j, :number)
      i = j + 1
    elseif isletter(c) || c == '_' || (c == '@' && i < n && isletter(chars[i+1]))
      j = i
      while j < n && (isname(chars[j+1]) || (lang.bang && chars[j+1] == '!' && !(j + 1 < n && chars[j+2] == '=')))
        j += 1
      end
      word = String(chars[i:j])
      kind = word in lang.keywords ? :keyword :
             word in lang.literals ? :number :
             c == '@' || (j < n && chars[j+1] == '(') ? :call :
             isuppercase(c) && any(islowercase, word) ? :type : :plain
      kind == :plain || add(i, j, kind)
      i = j + 1
    else
      i += 1
    end
  end
  plain <= n && push!(out, Token(plain - 1, String(chars[plain:n]), :plain))
  out
end

export Token, tokens
