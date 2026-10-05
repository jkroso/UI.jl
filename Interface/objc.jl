# A few helpers for calling macOS's Objective-C APIs, like AppKit, from Julia.
# They only work on macOS. Check `Sys.isapple()` before you use them.

const libobjc = "/usr/lib/libobjc.A.dylib"

"The Objective-C class called `name`"
cls(name) = ccall((:objc_getClass, libobjc), Ptr{Cvoid}, (Cstring,), name)
"The selector (method name) called `name`"
sel(name) = ccall((:sel_registerName, libobjc), Ptr{Cvoid}, (Cstring,), name)

"Send a message that takes no argument, or one object, and returns an object"
msg(obj, name) = ccall((:objc_msgSend, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}), obj, sel(name))
msg(obj, name, arg::Ptr) = ccall((:objc_msgSend, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), obj, sel(name), arg)

# `send` sends a message whose one argument is a plain value, like a Bool or an
# integer. `get_value(T, obj, name)` sends one that returns a plain value of
# type T. `ccall` needs its types written out, so each plain type gets a method.
for T in (Bool, Int, UInt, Float64)
  @eval send(obj, name, arg::$T) = ccall((:objc_msgSend, libobjc), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, $T), obj, sel(name), arg)
  @eval get_value(::Type{$T}, obj, name) = ccall((:objc_msgSend, libobjc), $T, (Ptr{Cvoid}, Ptr{Cvoid}), obj, sel(name))
end

nsstring(s) = ccall((:objc_msgSend, libobjc), Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, Cstring),
                    cls("NSString"), sel("stringWithUTF8String:"), s)
jstring(ns::Ptr{Cvoid}) = ns == C_NULL ? "" : unsafe_string(Ptr{UInt8}(msg(ns, "UTF8String")))

"Run `f` inside an autorelease pool, so the temporary objects it makes are freed"
with_pool(f) = begin
  pool = ccall((:objc_autoreleasePoolPush, libobjc), Ptr{Cvoid}, ())
  try
    f()
  finally
    ccall((:objc_autoreleasePoolPop, libobjc), Cvoid, (Ptr{Cvoid},), pool)
  end
end

export libobjc, cls, sel, msg, send, get_value, nsstring, jstring, with_pool
