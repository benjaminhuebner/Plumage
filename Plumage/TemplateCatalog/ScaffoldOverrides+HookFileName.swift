import Foundation

nonisolated extension ScaffoldOverrides {
    // On-disk filename for a hook stored by base name: the override file whose stem
    // matches (carrying `.py`/`.rb`), else the default `<base>.sh` — a Python hook
    // resolves to its real path while built-ins stay `.sh`.
    func hookFileName(forBase base: String) -> String {
        overrideFileNames(inRelativeDir: "hooks")
            .first { ($0 as NSString).deletingPathExtension == base } ?? "\(base).sh"
    }
}
