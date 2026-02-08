@use "github.com/jkroso/Prospects.jl" assoc @struct

abstract type Selector end

@struct IdentityKey <: Selector
const identitykey = IdentityKey()

"""
Used to select the key itself as the value
"""
@struct KeyKey(key::Any) <: Selector

get(data, key) = data[key]
get(data, s::Symbol) = getproperty(data, s)
get(data, ::IdentityKey) = data
get(data, k::KeyKey) = k.key

set(data, key, x) = assoc(data, key, x)
set(data, ::IdentityKey, x) = x
set(data::AbstractDict, k::KeyKey, x) = delete!(assoc(data, x, data[k.key]), k.key)
