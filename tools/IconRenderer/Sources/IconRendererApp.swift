import SwiftUI

@main
struct IconRendererApp: App {
    var body: some Scene {
        WindowGroup { ContentView().statusBarHidden(true) }
    }
}

struct ContentView: View {
    // simctl passes the variant via --setenv ENCLAVE_VARIANT
    private let variant: IconVariant = {
        let raw = ProcessInfo.processInfo.environment["ENCLAVE_VARIANT"] ?? IconVariant.allCases.first!.rawValue
        return IconVariant(rawValue: raw) ?? .frostClear
    }()
    var body: some View { IconView(variant: variant) }
}
