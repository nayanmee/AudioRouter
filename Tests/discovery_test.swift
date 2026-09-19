import Foundation
@main struct DiscoveryTests {
    static func main() {
        let roots: [Browser: Set<pid_t>] = [.safari: [101], .chrome: [202]]
        assert(AudioProcess.classify(bundle: "com.google.Chrome.helper", path: "", ancestors: [], roots: roots) == .chrome)
        assert(AudioProcess.classify(bundle: "com.apple.WebKit.GPU", path: "", ancestors: [303,101], roots: roots) == .safari)
        assert(AudioProcess.classify(bundle: "com.apple.WebKit.GPU", path: "", ancestors: [303,1], roots: roots) == nil)
        assert(AudioProcess.classify(bundle: "com.google.ChromeFake", path: "", ancestors: [], roots: roots) == nil)
        assert(AudioProcess.classify(bundle: "", path: "/Applications/Google Chrome.app/Contents/Frameworks/Helper", ancestors: [], roots: roots) == .chrome)
        let gpuPath = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        assert(AudioProcess.classify(bundle: "com.apple.WebKit.GPU", path: gpuPath, ancestors: [46289,1], roots: roots, displayName: "Safari Graphics and Media") == .safari)
        for name in ["Citrix Workspace Graphics and Media", "WebThumbnailExtension Graphics and Media", "Safari Technology Preview Graphics and Media", "Safari Graphics and Media extra", "com.apple.WebKit.GPU"] {
            assert(AudioProcess.classify(bundle: "com.apple.WebKit.GPU", path: gpuPath, ancestors: [1], roots: roots, displayName: name) == nil)
        }
        assert(AudioProcess.classify(bundle: "com.apple.WebKit.GPU", path: "/Applications/Other.app/Contents/MacOS/helper", ancestors: [1], roots: roots, displayName: "Safari Graphics and Media") == nil)
        assert(AudioProcess.classify(bundle: "com.apple.WebKit.GPU", path: gpuPath, ancestors: [1], roots: [:], displayName: "Safari Graphics and Media") == nil)
        let cursor = RoutableApplication(id: "com.todesktop.230313mzl4w4u92", name: "Cursor", bundlePath: "/Applications/Cursor.app", pids: [400])
        let safari = RoutableApplication(id: "com.apple.Safari", name: "Safari", bundlePath: "/Applications/Safari.app", pids: [101])
        let chrome = RoutableApplication(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app", pids: [202])
        let catalog = [cursor, safari, chrome]
        assert(AudioProcess.owner(bundle: cursor.id + ".helper", path: "", ancestors: [999,1], displayName: "Cursor Helper", applications: catalog) == cursor.id)
        assert(AudioProcess.owner(bundle: "", path: "", ancestors: [500,400], displayName: "Helper", applications: catalog) == cursor.id)
        assert(AudioProcess.owner(bundle: "", path: "/Applications/Cursor.app/Contents/Frameworks/Helper", ancestors: [1], displayName: "Helper", applications: catalog) == cursor.id)
        assert(AudioProcess.owner(bundle: cursor.id + "Fake", path: "/Applications/Cursor.app.extra/Contents/Helper", ancestors: [1], displayName: "Helper", applications: catalog) == nil)
        assert(AudioProcess.owner(bundle: "com.apple.WebKit.GPU", path: gpuPath, ancestors: [1], displayName: "Safari Graphics and Media", applications: catalog) == safari.id)
        assert(AudioProcess.owner(bundle: "com.apple.WebKit.GPU", path: gpuPath, ancestors: [1], displayName: "Citrix Workspace Graphics and Media", applications: catalog) == nil)
        print("PASS: browser/helper matching, launchd-owned Safari helper, unrelated WebKit exclusion, system path and host checks, Cursor helper/parent/path attribution")
    }
}
