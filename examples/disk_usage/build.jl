# Build the Disk Usage example as a standalone Mac app with JuliaC:
#
#     julia --project=. examples/disk_usage/build.jl
#
# It writes build/UI.jl Disk Usage.app. Add `--install` to copy it into
# /Applications too. See ../mac_app/build.jl for what the build needs and the
# settings it takes.
#
# icon.jl draws the app's icon, icon.png. The app scans with a worker thread for
# each of the Mac's cores. macOS asks before the app can read your Desktop,
# Documents and Downloads folders, and shows the reasons below.

include("../mac_app/build.jl")

reason = "Disk Usage reads the sizes of the files in it, to show what takes up space. It never changes or deletes them."
build_app(name="UI.jl Disk Usage", program="disk_usage", id="com.github.jkroso.ui-jl.disk-usage",
          entry=joinpath(@__DIR__, "app.jl"), threads="auto", icon=joinpath(@__DIR__, "icon.png"), plist="""
            <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
            <key>NSDesktopFolderUsageDescription</key><string>$reason</string>
            <key>NSDocumentsFolderUsageDescription</key><string>$reason</string>
            <key>NSDownloadsFolderUsageDescription</key><string>$reason</string>
            <key>NSRemovableVolumesUsageDescription</key><string>$reason</string>
            <key>NSNetworkVolumesUsageDescription</key><string>$reason</string>
          """)
