import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // Workaround for flutter/flutter#184571: CGEvent-injected Cmd+V (clipboard
  // managers, dictation tools) loses the Command modifier inside Flutter's
  // keyboard pipeline. Route it through the standard responder chain instead.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.type == .keyDown,
       event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
       event.charactersIgnoringModifiers == "v" {
      if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }
}
