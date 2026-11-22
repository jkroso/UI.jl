# Tests for the part of window.jl that needs no window: what a drop that holds
# no file becomes, and which button of the mouse a swipe stands for. Run them with `julia --project=. Interface/window_test.jl`.
# They use a pasteboard of their own, so the Mac's clipboard stays as it is.

@use Test: @test, @testset
@use "./objc" libobjc cls sel msg nsstring with_pool
@use "./window" dropped_file swap_drop! GLFW_DROP swipe_button
@use "github.com/jkroso/MiniFB.jl" Keys
@use GLFW

if Sys.isapple()
  Object = Ptr{Cvoid}
  board = msg(cls("NSPasteboard"), "pasteboardWithUniqueName")
  clear() = msg(board, "clearContents")
  put_text(kind, s) = ccall((:objc_msgSend, libobjc), Bool, (Object, Object, Object, Object), board, sel("setString:forType:"), nsstring(s), nsstring(kind))
  put_data(kind, bytes) = begin
    data = ccall((:objc_msgSend, libobjc), Object, (Object, Object, Ptr{UInt8}, UInt), cls("NSData"), sel("dataWithBytes:length:"), bytes, length(bytes))
    ccall((:objc_msgSend, libobjc), Bool, (Object, Object, Object, Object), board, sel("setData:forType:"), data, nsstring(kind))
  end

  @testset "a contact that's dropped is kept in a file" begin
    card = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Émile Zola\r\nEND:VCARD\r\n"
    with_pool() do
      # The Contacts app hands a contact over as the data of a vCard, beside the name as text
      clear(); put_data("public.vcard", Vector{UInt8}(card)); put_text("public.utf8-plain-text", "Émile Zola")
      path = dropped_file(board)
      @test endswith(path, ".vcf") && read(path, String) == card
      # Each drop has a file of its own
      @test dropped_file(board) != path
    end
  end

  @testset "a drop that holds a file, or nothing that's known, is left to GLFW" begin
    with_pool() do
      clear(); put_text("public.utf8-plain-text", "Some words")
      @test dropped_file(board) === nothing
      # A file from the Finder can come with other data. It stays a file.
      clear(); put_text("public.file-url", "file:///tmp/card.vcf"); put_data("public.vcard", Vector{UInt8}("BEGIN:VCARD\r\nEND:VCARD\r\n"))
      @test dropped_file(board) === nothing
      clear()
      @test dropped_file(board) === nothing
    end
  end

  @testset "the view's own method for a drop is kept under another name" begin
    view = cls("GLFWContentView")
    implementation(name) = ccall((:class_getMethodImplementation, libobjc), Object, (Object, Object), view, sel(name))
    if view != C_NULL
      glfws = implementation("performDragOperation:")
      @test swap_drop!(view)
      @test implementation("performDragOperation:") != glfws && implementation(GLFW_DROP) == glfws
      # A second time, as after this file is loaded again, the name still means GLFW's method
      @test swap_drop!(view)
      @test implementation(GLFW_DROP) == glfws
    end
    # A class with no method for a drop is left as it is
    @test !swap_drop!(cls("NSObject"))
  end

  msg(board, "releaseGlobally")
end

@testset "a swipe to the left is the back button, and to the right the forward button" begin
  # macOS gives a swipe to the left a deltaX of 1, and to the right -1
  @test swipe_button(1.0) == Keys.mouse_back
  @test swipe_button(-1.0) == Keys.mouse_forward
  # A swipe up or down has no deltaX, and stands for no button
  @test swipe_button(0.0) === nothing
end
