import SwiftUI

/// Isolated host for Apple's StoreKit test service; never packaged with PhotoCraft.
@main struct PhotoCraftTipsHost: App {
  var body: some Scene {
    WindowGroup {
      Text("Photato local StoreKit tests").padding(32)
        .onAppear { NSApp.activate() }
    }
  }
}
