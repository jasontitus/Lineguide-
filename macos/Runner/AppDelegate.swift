import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var pdfTextPlugin: PdfTextPlugin?
  private var memoryMonitorPlugin: MemoryMonitorPlugin?
  private var downloadPlugin: BackgroundDownloadPlugin?
  private var visionOcrPlugin: VisionOcrPlugin?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Register native macOS plugins on the Flutter engine's binary messenger
    guard let window = NSApplication.shared.windows.first,
          let flutterViewController = window.contentViewController as? FlutterViewController else {
      return
    }
    let messenger = flutterViewController.engine.binaryMessenger

    pdfTextPlugin = PdfTextPlugin(messenger: messenger)
    memoryMonitorPlugin = MemoryMonitorPlugin(messenger: messenger)
    downloadPlugin = BackgroundDownloadPlugin(messenger: messenger)
    visionOcrPlugin = VisionOcrPlugin(messenger: messenger)
  }
}
