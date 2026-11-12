# Reads Markdown one line at a time, the way a live-preview editor needs it.
# `classify` says what each line of a document is: a heading, a list item, a
# line of a code block and so on. `spans` splits the text of a line into runs
# of bold, italic, code and link text, and the markup characters around them.
# Columns count characters from 0, so column 0 is before the first character.

@use "github.com/jkroso/Prospects.jl" ["Enum" @Enum]

@Enum Kind blank paragraph heading bullet ordered blockquote fence code rule table

"What one line of a document is"
struct Line
  kind::Kind
  level::Int   # a heading's level, or how many spaces indent the line
  prefix::Int  # how many characters of indent and markup start the line
  lang::String # the language of the code block that a line of code is in
end

Line(kind::Kind, level::Int, prefix::Int) = Line(kind, level, prefix, "")

const HEADING = r"^(#{1,6})\s+"
const BULLET  = r"^(\s*)[-*+]\s+"
const ORDERED = r"^(\s*)\d+[.)]\s+"
const QUOTE   = r"^\s*>\s?"
const FENCE   = r"^\s*(```|~~~)\s*([^\s`]*)"
const RULE    = r"^\s*([-*_])(\s*\1){2,}\s*$"
const DIVIDER = r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"

"What `text` is. `lang` is the language of the code block it's inside, or nothing outside one."
Line(text::AbstractString, lang::Union{Nothing,AbstractString}=nothing) = begin
  m = match(FENCE, text)
  m === nothing || return Line(Kind.fence, 0, 0, m[2])
  lang === nothing || return Line(Kind.code, 0, 0, lang)
  isempty(strip(text)) && return Line(Kind.blank, 0, 0)
  m = match(HEADING, text)
  m === nothing || return Line(Kind.heading, length(m[1]), length(m.match))
  occursin(RULE, text) && return Line(Kind.rule, 0, 0)
  m = match(BULLET, text)
  m === nothing || return Line(Kind.bullet, length(m[1]), length(m.match))
  m = match(ORDERED, text)
  m === nothing || return Line(Kind.ordered, length(m[1]), length(m.match))
  m = match(QUOTE, text)
  m === nothing || return Line(Kind.blockquote, 0, length(m.match))
  startswith(lstrip(text), '|') && return Line(Kind.table, 0, 0)
  indent = length(text) - length(lstrip(text))
  Line(Kind.paragraph, indent, indent)
end

"What each line of a document is"
classify(lines) = begin
  lang = nothing
  map(lines) do text
    line = Line(text, lang)
    # The line that opens a code block names its language
    line.kind == Kind.fence && (lang = lang === nothing ? line.lang : nothing)
    line
  end
end

"A run of a line's text that is all drawn one way"
struct Span
  col::Int       # the column of its first character
  text::String
  bold::Bool
  italic::Bool
  code::Bool
  strike::Bool
  link::String   # where it goes when it's the text of a link
  markup::Bool   # true for characters like ** that only say how to draw others
end

struct Style
  bold::Bool
  italic::Bool
  strike::Bool
  link::String
end

Style() = Style(false, false, false, "")

isword(c::Char) = isletter(c) || isdigit(c)

"The index where `delim` next starts in `chars[from:to]`, or 0"
find(chars, delim::String, from, to) = begin
  n = length(delim)
  for i in from:to-n+1
    all(chars[i+k-1] == delim[k] for k in 1:n) && return i
  end
  0
end

"""
Where the run that opens with `delim` at `i` closes, or 0 if it doesn't. The
text between can't start or end with a space, and an _ inside a word like
snake_case doesn't count.
"""
closer(chars, delim::String, i, to) = begin
  n = length(delim)
  start = i + n
  (start <= to && !isspace(chars[start])) || return 0
  delim[1] == '_' && i > 1 && isword(chars[i-1]) && return 0
  j = start + 1
  while (j = find(chars, delim, j, to)) != 0
    ok = !isspace(chars[j-1]) && !(delim[1] == '_' && j + n <= to && isword(chars[j+n]))
    # A lone * can't close on the first star of a **
    # In ***both***, the ** closes on the last two stars
    ok && n == 2 && j + 2 <= to && chars[j+2] == delim[1] && return j + 1
    ok && !(n == 1 && j < to && chars[j+1] == delim[1]) && return j
    j += 1
  end
  0
end

"Split `chars[from:to]` into spans, added to `out`. `offset` is the column of `chars[1]`."
function scan!(out, chars, from, to, style::Style, offset)
  plain = from
  emit(i, j; markup=false, code=false, s=style) = i <= j &&
    push!(out, Span(offset + i - 1, String(chars[i:j]), s.bold, s.italic, code, s.strike, s.link, markup))
  i = from
  while i <= to
    c = chars[i]
    next = i < to ? chars[i+1] : '\0'
    delim, inner = "", style
    if c == '\\' && i < to && ispunct(next)
      emit(plain, i - 1); emit(i, i, markup=true)
      plain = i + 1
      i += 2
      continue
    elseif c == '`'
      j = find(chars, "`", i + 1, to)
      if j > i + 1
        emit(plain, i - 1); emit(i, i, markup=true); emit(i + 1, j - 1, code=true); emit(j, j, markup=true)
        plain = i = j + 1
        continue
      end
    elseif c == '['
      j = find(chars, "](", i + 1, to)
      k = j == 0 ? 0 : find(chars, ")", j + 2, to)
      if j > i + 1 && k != 0
        url = String(chars[j+2:k-1])
        emit(plain, i - 1); emit(i, i, markup=true)
        scan!(out, chars, i + 1, j - 1, Style(style.bold, style.italic, style.strike, url), offset)
        emit(j, k, markup=true)
        plain = i = k + 1
        continue
      end
    elseif (c == '*' || c == '_') && next == c
      delim, inner = string(c, c), Style(true, style.italic, style.strike, style.link)
    elseif c == '*' || c == '_'
      delim, inner = string(c), Style(style.bold, true, style.strike, style.link)
    elseif c == '~' && next == '~'
      delim, inner = "~~", Style(style.bold, style.italic, true, style.link)
    end
    j = isempty(delim) ? 0 : closer(chars, delim, i, to)
    if j == 0
      i += max(1, length(delim))
      continue
    end
    n = length(delim)
    emit(plain, i - 1); emit(i, i + n - 1, markup=true)
    scan!(out, chars, i + n, j - 1, inner, offset)
    emit(j, j + n - 1, markup=true)
    plain = i = j + n
  end
  emit(plain, to)
  out
end

"The spans of `text`, whose first character is at column `offset` of its line"
spans(text::AbstractString, offset::Int=0) = begin
  chars = collect(text)
  scan!(Span[], chars, 1, length(chars), Style(), offset)
end

"True for the line of dashes under a table's headings"
isdivider(text::AbstractString) = occursin(DIVIDER, text) && occursin('-', text)

"""
One cell of a row of a table. Its text runs from column `lo` to column `hi`,
without the spaces around it. The caret can go as far as `limit`, which is
past `hi` when spaces have been typed after the text.
"""
struct Cell
  lo::Int
  hi::Int
  limit::Int
end

"The cells of one row of a table"
tablecells(text::AbstractString) = begin
  chars = collect(text)
  n = length(chars)
  pipes = [i for i in 1:n if chars[i] == '|' && (i == 1 || chars[i-1] != '\\')]
  out = Cell[]
  isempty(pipes) && return out
  ends = pipes[2:end]
  # Text after the last | is a cell too
  any(!isspace, chars[last(pipes)+1:end]) && push!(ends, n + 1)
  for (p, q) in zip(pipes, ends)
    # The cell is chars[p+1:q-1], and column p is just after the first |
    a = findnext(!isspace, chars, p + 1)
    if a === nothing || a >= q
      size = q - 1 - p
      lo = p + min(1, size)
      push!(out, Cell(lo, lo, max(lo, q - 1 - (size >= 2 ? 1 : 0))))
    else
      z = findprev(!isspace, chars, q - 1)
      # One space before the closing | is left alone
      push!(out, Cell(a - 1, z, q > n ? n : z + max(0, q - 2 - z)))
    end
  end
  out
end

"How many words are in a document"
words(lines) = sum(text -> count(_ -> true, eachmatch(r"[\p{L}\p{N}][\p{L}\p{N}'’-]*", text)), lines, init=0)

export Kind, Line, Span, Cell, classify, spans, tablecells, isdivider, words
