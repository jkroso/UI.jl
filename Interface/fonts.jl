@use "github.com/jkroso/MiniFB.jl/skia" SkiaFont fontmgr
@use "github.com/jkroso/MiniFB.jl" flt
@use Fontconfig
@use Skia
@use "./abstract" epoch

# Typefaces loaded from font files. Each is stored under its family name and
# under "family:Weight" (e.g. "Quicksand:Bold"), matching the `family` and
# `subfamily` fields on Text. Skia's default font manager only knows about
# installed fonts, so these take priority over it. A weight that wasn't loaded
# comes from the installed font of that family, if there is one.
const _typefaces = Dict{String,Ptr{Skia.sk_typeface_t}}()

const weight_names = [100 => "Thin", 200 => "ExtraLight", 300 => "Light", 400 => "Regular",
                      500 => "Medium", 600 => "SemiBold", 700 => "Bold", 800 => "ExtraBold", 900 => "Black"]

"The conventional style name for a numeric font weight"
weight_name(weight::Integer) = last(argmin(((w, _),) -> abs(w - weight), weight_names))

"True when a style name like \"Italic\" or \"Bold Italic\" asks for slanted letters"
isitalic(style::AbstractString) = occursin(r"italic|oblique"i, style)

# Other names that fonts give their weights
const weight_aliases = Dict("hairline" => 100, "ultralight" => 200, "demibold" => 600, "heavy" => 800, "ultrabold" => 800,
                            "extrablack" => 900, "ultrablack" => 900, "roman" => 400, "normal" => 400)

"The numeric weight for a style name like \"Bold\" or \"Semi Bold Italic\", or 400 if it isn't one"
weight_of(style::AbstractString) = begin
  key = lowercase(replace(style, r"italic|oblique"i => "", r"[\s_-]" => ""))
  i = findfirst(((_, name),) -> lowercase(name) == key, weight_names)
  i === nothing ? get(weight_aliases, key, 400) : first(weight_names[i])
end

"A face's name in a form that ignores case and spaces: \"Semi Bold Italic\" and \"SemiBold Italic\" are one name"
face_key(name::AbstractString) = lowercase(replace(name, r"[\s_-]" => ""))

const FontFace = @NamedTuple{name::String, weight::Int, italic::Bool, width::Int}
const _faces = Dict{String,Vector{FontFace}}()

"""
The faces of the installed font `family`, in the Mac's order: the name of
each, like "Light Italic", its weight, whether it's italic, and how wide it
is, where 5 is the usual width. A font's own names and the Mac's weights don't
always agree with the usual ones: Helvetica Neue's UltraLight is lighter than
its Thin, and the Mac says that Source Code Pro's ExtraLight weighs 300 and
its Light 342. There are none when the Mac has no font of that family, or
hides its faces, as it does for its own fonts whose names start with a dot.
"""
installed_faces(family::AbstractString) = get!(_faces, String(family)) do
  faces = FontFace[]
  set = Skia.sk_fontmgr_match_family(fontmgr[], String(family))
  set == C_NULL && return faces
  for i in 0:Skia.sk_fontstyleset_get_count(set)-1
    style = Skia.sk_fontstyle_new(Int32(400), Int32(Skia.SK_FONT_STYLE_WIDTH_NORMAL), Skia.SK_FONT_STYLE_SLANT_UPRIGHT)
    name = Skia.sk_string_new_empty()
    Skia.sk_fontstyleset_get_style(set, Cint(i), style, name)
    push!(faces, (name=unsafe_string(Skia.sk_string_get_c_str(name)), weight=Int(Skia.sk_fontstyle_get_weight(style)),
                  italic=Skia.sk_fontstyle_get_slant(style) != Skia.SK_FONT_STYLE_SLANT_UPRIGHT,
                  width=Int(Skia.sk_fontstyle_get_width(style))))
    Skia.sk_string_delete(name)
    Skia.sk_fontstyle_delete(style)
  end
  Skia.sk_fontstyleset_unref(set)
  faces
end

"The installed face of `family` called `name`, like \"Light Italic\", and its typeface, or nothing when it has no face of that name"
named_face(family::AbstractString, name::AbstractString) = begin
  key = face_key(isempty(name) ? "Regular" : name)
  i = findfirst(f -> face_key(f.name) == key, installed_faces(family))
  i === nothing && return nothing
  set = Skia.sk_fontmgr_match_family(fontmgr[], String(family))
  typeface = Skia.sk_fontstyleset_create_typeface(set, Cint(i - 1))
  Skia.sk_fontstyleset_unref(set)
  typeface == C_NULL ? nothing : (installed_faces(family)[i], typeface)
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
  italic = Skia.sk_fontstyle_get_slant(style) != Skia.SK_FONT_STYLE_SLANT_UPRIGHT
  Skia.sk_fontstyle_delete(style)
  # The plain family name keeps the upright weight closest to Regular
  current = get(_typefaces, family, nothing)
  if !italic && (current === nothing || abs(weight - 400) < abs(registered_weight(current) - 400))
    _typefaces[family] = typeface
  end
  # A slanted face has its own name, like "Italic" or "Bold Italic", so it doesn't take the place of the upright one
  name = weight_name(weight)
  _typefaces["$family:$(italic ? (name == "Regular" ? "Italic" : "$name Italic") : name)"] = typeface
  empty!(_skia_fonts) # a family name may now resolve to a different face
  epoch[] += 1         # and text laid out with the old face may now be another size
  family
end

registered_weight(typeface) = begin
  style = Skia.sk_typeface_get_fontstyle(typeface)
  weight = Skia.sk_fontstyle_get_weight(style)
  Skia.sk_fontstyle_delete(style)
  weight
end

const _skia_fonts = Dict{Tuple{String,String,Float32},SkiaFont}()

# Typefaces and fonts point into Skia's memory, which only lasts as long as the
# process. A compiled app starts with whatever was cached when it was built, so
# throw those away.
__init__() = (empty!(_typefaces); empty!(_skia_fonts); empty!(_faces))

"""
A Skia font for `family` at `size`, cached so drawing every frame doesn't
rebuild it. Families added with `register_font` win over installed ones. For
an installed family, `subfamily` picks the face by its name, e.g. "Semibold"
or "Light Italic". A family without a face of that name gets the weight that
the name says, and "Italic" or "Bold Italic" picks slanted letters.
"""
skia_font(family::AbstractString, size, subfamily::AbstractString="") = begin
  sz = flt(size)
  get!(_skia_fonts, (String(family), String(subfamily), sz)) do
    typeface = get(_typefaces, "$family:$subfamily", nothing)
    if typeface === nothing
      named = named_face(family, subfamily)
      if named !== nothing
        face, typeface = named
        raw = Skia.sk_font_new_with_values(typeface, sz, 1f0, 0f0)
        slant = face.italic ? Skia.SK_FONT_STYLE_SLANT_ITALIC : Skia.SK_FONT_STYLE_SLANT_UPRIGHT
        weight = Skia.sk_font_style_weight_t(clamp(100round(Int, face.weight / 100), 100, 900))   # one of the nine that Skia names
        return SkiaFont(String(family), weight, slant, sz, raw)
      end
      # A loaded family that's installed too gets the installed weight, not a loaded one of another weight
      typeface = isempty(installed_faces(family)) ? get(_typefaces, family, nothing) : nothing
    end
    typeface === nothing && return installed_font(String(family), sz, weight_of(subfamily), isitalic(subfamily))
    raw = Skia.sk_font_new_with_values(typeface, sz, 1f0, 0f0)
    SkiaFont(String(family), Skia.SK_FONT_STYLE_WEIGHT_NORMAL, Skia.SK_FONT_STYLE_SLANT_UPRIGHT, sz, raw)
  end
end

"The installed typeface that Skia finds nearest to a family, weight and slant"
match_typeface(family::String, weight::Integer, slant) = begin
  style = Skia.sk_fontstyle_new(Int32(weight), Int32(Skia.SK_FONT_STYLE_WIDTH_NORMAL), slant)
  typeface = Skia.sk_fontmgr_match_family_style(fontmgr[], family, style)
  Skia.sk_fontstyle_delete(style)
  typeface
end

"The installed font that best matches a family, weight and slant"
installed_font(family::String, size::Float32, weight::Integer, italic::Bool) = begin
  slant = italic ? Skia.SK_FONT_STYLE_SLANT_ITALIC : Skia.SK_FONT_STYLE_SLANT_UPRIGHT
  typeface = match_typeface(family, weight, slant)
  # As in CSS, a family with no medium weight gives its regular one for 500, where Skia would give its bold
  if weight == 500 && typeface != C_NULL && registered_weight(typeface) > 500
    typeface = match_typeface(family, 400, slant)
  end
  raw = Skia.sk_font_new_with_values(typeface, size, 1f0, 0f0)
  SkiaFont(family, Skia.sk_font_style_weight_t(weight), slant, size, raw)
end

export register_font, skia_font, installed_faces
