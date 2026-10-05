@use "github.com/jkroso/MiniFB.jl/skia" SkiaFont fontmgr
@use "github.com/jkroso/MiniFB.jl" flt
@use Fontconfig
@use Skia

# Typefaces loaded from font files. Each is stored under its family name and
# under "family:Weight" (e.g. "Quicksand:Bold"), matching the `family` and
# `subfamily` fields on Text. Skia's default font manager only knows about
# installed fonts, so these take priority over it.
const _typefaces = Dict{String,Ptr{Skia.sk_typeface_t}}()

const weight_names = [100 => "Thin", 200 => "ExtraLight", 300 => "Light", 400 => "Regular",
                      500 => "Medium", 600 => "SemiBold", 700 => "Bold", 800 => "ExtraBold", 900 => "Black"]

"The conventional style name for a numeric font weight"
weight_name(weight::Integer) = last(argmin(((w, _),) -> abs(w - weight), weight_names))

"The numeric weight for a style name like \"Bold\" or \"Semi Bold\", or 400 if it isn't one"
weight_of(style::AbstractString) = begin
  key = lowercase(replace(style, r"[\s_-]" => ""))
  i = findfirst(((_, name),) -> lowercase(name) == key, weight_names)
  i === nothing ? 400 : first(weight_names[i])
end

"""
Make the font file at `path` usable by its family name, without installing it.
Layout measures text through Fontconfig and drawing goes through Skia, so the
file is registered with both. Returns the family name to pass to `Text(family=…)`.
When you register several weights of one family, pick one with
`Text(family="Quicksand", subfamily="Bold")`.
"""
register_font(path::AbstractString) = begin
  path = abspath(path)
  isfile(path) || error("Font not found: $path")
  ok = ccall((:FcConfigAppFontAddFile, Fontconfig.libfontconfig), Cint, (Ptr{Cvoid}, Cstring), C_NULL, path)
  ok == 0 && error("Fontconfig could not load $path")
  bytes = read(path)
  data = Skia.sk_data_new_with_copy(pointer(bytes), UInt64(length(bytes)))
  typeface = Skia.sk_fontmgr_create_from_data(fontmgr[], data, Int32(0))
  Skia.sk_data_unref(data)
  typeface == C_NULL && error("Skia could not load $path")
  name = Skia.sk_typeface_get_family_name(typeface)
  family = unsafe_string(Skia.sk_string_get_c_str(name))
  Skia.sk_string_delete(name)
  style = Skia.sk_typeface_get_fontstyle(typeface)
  weight = Skia.sk_fontstyle_get_weight(style)
  Skia.sk_fontstyle_delete(style)
  # The plain family name keeps the weight closest to Regular
  current = get(_typefaces, family, nothing)
  if current === nothing || abs(weight - 400) < abs(registered_weight(current) - 400)
    _typefaces[family] = typeface
  end
  _typefaces["$family:$(weight_name(weight))"] = typeface
  empty!(_skia_fonts) # a family name may now resolve to a different face
  family
end

registered_weight(typeface) = begin
  style = Skia.sk_typeface_get_fontstyle(typeface)
  weight = Skia.sk_fontstyle_get_weight(style)
  Skia.sk_fontstyle_delete(style)
  weight
end

const _skia_fonts = Dict{Tuple{String,String,Float32},SkiaFont}()

"""
A Skia font for `family` at `size`, cached so drawing every frame doesn't
rebuild it. Families added with `register_font` win over installed ones. For
an installed family, `subfamily` picks the weight by name, e.g. "Semibold".
"""
skia_font(family::AbstractString, size, subfamily::AbstractString="") = begin
  sz = flt(size)
  get!(_skia_fonts, (String(family), String(subfamily), sz)) do
    typeface = get(_typefaces, "$family:$subfamily", get(_typefaces, family, nothing))
    typeface === nothing && return SkiaFont(String(family), size, Skia.sk_font_style_weight_t(weight_of(subfamily)))
    raw = Skia.sk_font_new_with_values(typeface, sz, 1f0, 0f0)
    SkiaFont(String(family), Skia.SK_FONT_STYLE_WEIGHT_NORMAL, Skia.SK_FONT_STYLE_SLANT_UPRIGHT, sz, raw)
  end
end

export register_font, skia_font
