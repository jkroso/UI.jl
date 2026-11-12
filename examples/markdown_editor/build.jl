# Build the Markdown editor example as a standalone Mac app with JuliaC:
#
#     julia --project=. examples/markdown_editor/build.jl
#
# It writes build/UI.jl Markdown.app. Add `--install` to copy it into
# /Applications too. See ../mac_app/build.jl for what the build needs and the
# settings it takes.
#
# Leave APP_TRIM at no. A sheet and a live block run Julia code that the app
# has never seen, and a trimmed app can't compile new code.
#
# icon.jl draws the app's icon, icon.png.

include("../mac_app/build.jl")

# macOS asks before the app can read your Desktop, Documents and Downloads
# folders, and shows this reason
reason = "The Markdown editor opens the Markdown files in it, and saves a file when you press ⌘S."
build_app(name="UI.jl Markdown", program="markdown_editor", id="com.github.jkroso.ui-jl.markdown",
          entry=joinpath(@__DIR__, "app.jl"), icon=joinpath(@__DIR__, "icon.png"), plist="""
            <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
            <key>NSDesktopFolderUsageDescription</key><string>$reason</string>
            <key>NSDocumentsFolderUsageDescription</key><string>$reason</string>
            <key>NSDownloadsFolderUsageDescription</key><string>$reason</string>
          """)
