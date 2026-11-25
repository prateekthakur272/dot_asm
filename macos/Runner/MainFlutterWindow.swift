import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Avoid the black flash on launch: keep the window invisible until Dart
    // has rendered its first frame (main.dart then calls setOpacity(1) and
    // show()), and match the app background in case it is revealed earlier.
    let isDark = NSApp.effectiveAppearance
      .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    self.backgroundColor = isDark
      ? NSColor(srgbRed: 0x13 / 255.0, green: 0x14 / 255.0, blue: 0x17 / 255.0, alpha: 1)
      : NSColor(srgbRed: 0xF4 / 255.0, green: 0xF6 / 255.0, blue: 0xF9 / 255.0, alpha: 1)
    self.alphaValue = 0

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
