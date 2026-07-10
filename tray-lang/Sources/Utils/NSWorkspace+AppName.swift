import AppKit

extension NSWorkspace {
    func applicationName(for bundleIdentifier: String) -> String {
        if let url = urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: url) {
            return bundle.localizedInfoDictionary?["CFBundleName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? bundleIdentifier
        }
        return bundleIdentifier
    }
}
