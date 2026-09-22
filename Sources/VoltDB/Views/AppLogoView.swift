import SwiftUI
import AppKit

struct AppLogoView: View {
    var size: CGFloat = 16
    
    var body: some View {
        if let nsImg = loadAppIcon() {
            Image(nsImage: nsImg)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .cornerRadius(size * 0.22)
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
        } else {
            Image(systemName: "cylinder.split.1x2.fill")
                .font(.system(size: size * 0.85, weight: .bold))
                .foregroundColor(AppTheme.accent)
        }
    }
    
    private func loadAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let path = Bundle.main.resourcePath?.appending("/AppIcon.png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        if let path = Bundle.main.resourcePath?.appending("/Resources/AppIcon.png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        let devPath = "Sources/VoltDB/Resources/AppIcon.png"
        if let img = NSImage(contentsOfFile: devPath) {
            return img
        }
        return nil
    }
}
