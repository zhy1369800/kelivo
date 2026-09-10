 import Flutter
 import UIKit
 import AuthenticationServices
 import UserNotifications
import ActivityKit
import EventKit
import SwiftUI
import Translation
import UniformTypeIdentifiers


@main
@objc class AppDelegate: FlutterAppDelegate {
   private let fileSaveHandler = NativeFileSaveHandler()
   private let backgroundGenerationHandler = MobileBackgroundHandler()
   private let mcpOAuthHandler = IosMcpOAuthHandler()
   private let deviceLocalToolsHandler = DeviceLocalToolsHandler()
  private let mapKitHandler = MapKitHandler()
  private let weatherKitHandler = WeatherKitHandler()
  private let bleBridgeHandler = BleBridgeHandler()
  private let userNotificationHandler = UserNotificationHandler()
  private let deviceInfoHandler = DeviceInfoHandler()
  private let healthKitHandler = HealthKitHandler()
  private let calendarEventHandler = CalendarEventHandler()
  private let reminderTaskHandler = ReminderTaskHandler()
  private let alarmTimerHandler = AlarmTimerHandler()
  private let appleVisionHandler = AppleVisionHandler()
  private let appleSpeechRecognizerHandler = AppleSpeechRecognizerHandler()
  private let appleSpeechSynthesizerHandler = AppleSpeechSynthesizerHandler()
  private let fileSystemHandler = FileSystemHandler()
  private let iosTranslationHandler = IosTranslationHandler()
  private let incomingShareHandler = IosIncomingShareHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // FlutterAppDelegate forwards foreground presentation and cold/warm taps
    // to flutter_local_notifications. Assigning a delegate requests no access.
    UNUserNotificationCenter.current().delegate = self
    if let controller = window?.rootViewController as? FlutterViewController {
      incomingShareHandler.register(messenger: controller.binaryMessenger)
      let clipboardChannel = FlutterMethodChannel(name: "app.clipboard", binaryMessenger: controller.binaryMessenger)
      clipboardChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "getClipboardImages" {
          var paths: [String] = []
          if let image = UIPasteboard.general.image {
            if let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) {
              let tmp = NSTemporaryDirectory()
              let filename = "pasted_\(Int(Date().timeIntervalSince1970 * 1000)).png"
              let url = URL(fileURLWithPath: tmp).appendingPathComponent(filename)
              do {
                try data.write(to: url)
                paths.append(url.path)
              } catch {
                // ignore write error
              }
            }
          }
          result(paths)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      let fileSaveChannel = FlutterMethodChannel(name: "app.file_save", binaryMessenger: controller.binaryMessenger)
      fileSaveHandler.presentingViewController = controller
      fileSaveChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard call.method == "saveFileFromPath" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.fileSaveHandler.handle(call: call, result: result)
      }

      backgroundGenerationHandler.configure(messenger: controller.binaryMessenger)

      let mcpOAuthChannel = FlutterMethodChannel(name: "app.mcp_oauth", binaryMessenger: controller.binaryMessenger)
      mcpOAuthHandler.presentationAnchor = window
      mcpOAuthChannel.setMethodCallHandler { [weak self] call, result in
        self?.mcpOAuthHandler.handle(call: call, result: result)
      }

      let iosTranslationChannel = FlutterMethodChannel(name: "app.ios_translation", binaryMessenger: controller.binaryMessenger)
      iosTranslationHandler.presentingViewController = controller
      iosTranslationChannel.setMethodCallHandler { [weak self] call, result in
        self?.iosTranslationHandler.handle(call: call, result: result)
      }
 
       let deviceToolsChannel = FlutterMethodChannel(name: "app.device_tools", binaryMessenger: controller.binaryMessenger)
       deviceToolsChannel.setMethodCallHandler { [weak self] call, result in
         self?.deviceLocalToolsHandler.handle(call: call, result: result)
       }

      let mapKitChannel = FlutterMethodChannel(name: "app.map_kit", binaryMessenger: controller.binaryMessenger)
      mapKitChannel.setMethodCallHandler { [weak self] call, result in
        self?.mapKitHandler.handle(call: call, result: result)
      }

      let weatherKitChannel = FlutterMethodChannel(name: "app.weather_kit", binaryMessenger: controller.binaryMessenger)
      weatherKitChannel.setMethodCallHandler { [weak self] call, result in
        self?.weatherKitHandler.handle(call: call, result: result)
      }

      let bleBridgeChannel = FlutterMethodChannel(name: "app.ble_bridge", binaryMessenger: controller.binaryMessenger)
      bleBridgeChannel.setMethodCallHandler { [weak self] call, result in
        self?.bleBridgeHandler.handle(call: call, result: result)
      }

      let userNotificationChannel = FlutterMethodChannel(name: "app.user_notification", binaryMessenger: controller.binaryMessenger)
      userNotificationChannel.setMethodCallHandler { [weak self] call, result in
        self?.userNotificationHandler.handle(call: call, result: result)
      }

      let deviceInfoChannel = FlutterMethodChannel(name: "app.device_info", binaryMessenger: controller.binaryMessenger)
      deviceInfoChannel.setMethodCallHandler { [weak self] call, result in
        self?.deviceInfoHandler.handle(call: call, result: result)
      }

      let healthKitChannel = FlutterMethodChannel(name: "app.health_kit", binaryMessenger: controller.binaryMessenger)
      healthKitChannel.setMethodCallHandler { [weak self] call, result in
        self?.healthKitHandler.handle(call: call, result: result)
      }

      let calendarEventChannel = FlutterMethodChannel(name: "app.calendar_event", binaryMessenger: controller.binaryMessenger)
      calendarEventChannel.setMethodCallHandler { [weak self] call, result in
        self?.calendarEventHandler.handle(call: call, result: result)
      }

      let reminderTaskChannel = FlutterMethodChannel(name: "app.reminder_task", binaryMessenger: controller.binaryMessenger)
      reminderTaskChannel.setMethodCallHandler { [weak self] call, result in
        self?.reminderTaskHandler.handle(call: call, result: result)
      }

      let alarmTimerChannel = FlutterMethodChannel(name: "app.alarm_timer", binaryMessenger: controller.binaryMessenger)
      alarmTimerChannel.setMethodCallHandler { [weak self] call, result in
        self?.alarmTimerHandler.handle(call: call, result: result)
      }

      let appleVisionChannel = FlutterMethodChannel(name: "app.apple_vision", binaryMessenger: controller.binaryMessenger)
      appleVisionChannel.setMethodCallHandler { [weak self] call, result in
        self?.appleVisionHandler.handle(call: call, result: result)
      }

      let speechRecognizerChannel = FlutterMethodChannel(name: "app.speech_recognizer", binaryMessenger: controller.binaryMessenger)
      speechRecognizerChannel.setMethodCallHandler { [weak self] call, result in
        self?.appleSpeechRecognizerHandler.handle(call: call, result: result)
      }

      let speechSynthesizerChannel = FlutterMethodChannel(name: "app.speech_synthesizer", binaryMessenger: controller.binaryMessenger)
      speechSynthesizerChannel.setMethodCallHandler { [weak self] call, result in
        self?.appleSpeechSynthesizerHandler.handle(call: call, result: result)
      }

      let fileSystemChannel = FlutterMethodChannel(name: "app.file_system", binaryMessenger: controller.binaryMessenger)
      fileSystemChannel.setMethodCallHandler { [weak self] call, result in
        self?.fileSystemHandler.handle(call: call, result: result)
      }

      if #available(iOS 16.1, *) {
        VoiceChatLiveActivityHandler.shared.setup(binaryMessenger: controller.binaryMessenger)
      }

      WorkspacePlugin.register(messenger: controller.binaryMessenger, presenter: controller)

      // Free space on the volume holding the app's data. Uses the "important
      // usage" capacity, which is what iOS will actually free up for data the
      // app cannot regenerate -- the plain available-capacity value understates
      // it and would make the app skip copies it could have made.
      let storageChannel = FlutterMethodChannel(name: "app.device_storage", binaryMessenger: controller.binaryMessenger)
      storageChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "freeBytes":
          guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            result(nil)
            return
          }
          do {
            let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
              result(NSNumber(value: capacity))
              return
            }
          } catch {
            // Fall through: the caller treats a missing answer as "unknown".
          }
          result(nil)

        // Local database copies live under Documents, which iCloud backs up in
        // full. They can reach gigabytes and are reproducible from the live
        // database, so backing them up would bloat -- and can break -- the
        // user's iCloud backup without protecting anything new.
        case "excludeFromBackup":
          guard
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String,
            !path.isEmpty
          else {
            result(FlutterError(code: "invalid_args", message: "Missing path.", details: nil))
            return
          }
          var url = URL(fileURLWithPath: path)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          do {
            try url.setResourceValues(values)
            result(true)
          } catch {
            result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
          }

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    backgroundGenerationHandler.prepareForTermination()
    super.applicationWillTerminate(application)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if backgroundGenerationHandler.receive(url) { return true }
    if incomingShareHandler.receive(url) { return true }
    if url.scheme == "kelivo" {
      if url.host == "oauth-return" {
        return true
      }
      if url.host == "voice" && url.path == "/stop" {
        if #available(iOS 16.1, *) {
          VoiceChatLiveActivityHandler.shared.handleStopFromWidget()
        }
        return true
      }
    }
    return super.application(app, open: url, options: options)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}

private final class IosTranslationHandler {
  weak var presentingViewController: UIViewController?
  private var hostingController: UIViewController?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      if #available(iOS 17.4, *) {
        result(true)
      } else {
        result(false)
      }
    case "present":
      guard #available(iOS 17.4, *) else {
        result(false)
        return
      }
      let arguments = call.arguments as? [String: Any]
      guard
        let text = arguments?["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        let anchorX = arguments?["anchorX"] as? Double,
        let anchorY = arguments?["anchorY"] as? Double,
        let presenter = presentingViewController,
        presenter.viewIfLoaded?.window != nil
      else {
        result(false)
        return
      }
      present(
        text: text,
        anchor: CGPoint(x: anchorX, y: anchorY),
        in: presenter
      )
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 17.4, *)
  private func present(text: String, anchor: CGPoint, in presenter: UIViewController) {
    removeHostingController()

    let bounds = presenter.view.bounds
    let point = CGPoint(
      x: min(max(anchor.x, bounds.minX + 1), bounds.maxX - 1),
      y: min(max(anchor.y, bounds.minY + 1), bounds.maxY - 1)
    )
    let hostingController = UIHostingController(
      rootView: NativeTranslationPresenter(text: text) { [weak self] in
        self?.removeHostingController()
      }
    )
    hostingController.view.backgroundColor = .clear
    hostingController.view.frame = CGRect(
      x: point.x - 1,
      y: point.y - 1,
      width: 2,
      height: 2
    )
    presenter.addChild(hostingController)
    presenter.view.addSubview(hostingController.view)
    hostingController.didMove(toParent: presenter)
    self.hostingController = hostingController
  }

  private func removeHostingController() {
    guard let hostingController else { return }
    hostingController.willMove(toParent: nil)
    hostingController.view.removeFromSuperview()
    hostingController.removeFromParent()
    self.hostingController = nil
  }
}

@available(iOS 17.4, *)
private struct NativeTranslationPresenter: View {
  let text: String
  let onDismiss: () -> Void
  @State private var isPresented = false

  var body: some View {
    Color.clear
      .translationPresentation(isPresented: $isPresented, text: text)
      .onAppear {
        DispatchQueue.main.async {
          isPresented = true
        }
      }
      .onChange(of: isPresented) { visible in
        if !visible {
          onDismiss()
        }
      }
  }
}

private final class IosMcpOAuthHandler: NSObject, ASWebAuthenticationPresentationContextProviding {
  weak var presentationAnchor: UIWindow?
  private var session: ASWebAuthenticationSession?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "authenticate":
      guard session == nil else {
        result(FlutterError(code: "authorization_in_progress", message: "An authorization session is already in progress.", details: nil))
        return
      }
      let arguments = call.arguments as? [String: Any]
      guard
        let urlString = arguments?["url"] as? String,
        let url = URL(string: urlString),
        let callbackScheme = arguments?["callbackScheme"] as? String,
        !callbackScheme.isEmpty
      else {
        result(FlutterError(code: "invalid_arguments", message: "A valid authorization URL and callback scheme are required.", details: nil))
        return
      }

      let authenticationSession = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: callbackScheme
      ) { [weak self] callbackURL, error in
        self?.session = nil
        if let callbackURL {
          result(callbackURL.absoluteString)
          return
        }
        let nsError = error as NSError?
        let cancelled = nsError?.domain == ASWebAuthenticationSessionErrorDomain && nsError?.code == 1
        result(
          FlutterError(
            code: cancelled ? "authorization_cancelled" : "authorization_failed",
            message: error?.localizedDescription ?? "Authorization did not return a callback URL.",
            details: nil
          )
        )
      }
      authenticationSession.presentationContextProvider = self
      authenticationSession.prefersEphemeralWebBrowserSession = false
      session = authenticationSession
      if !authenticationSession.start() {
        session = nil
        result(FlutterError(code: "authorization_failed", message: "Could not start the authorization session.", details: nil))
      }
    case "cancel":
      session?.cancel()
      session = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    if let presentationAnchor {
      return presentationAnchor
    }
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
        return window
      }
    }
    return UIWindow()
  }
}

private final class NativeFileSaveHandler: NSObject, UIDocumentPickerDelegate {
  weak var presentingViewController: UIViewController?
  private var pendingResult: FlutterResult?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if pendingResult != nil {
      result(FlutterError(code: "busy", message: "Another save operation is already in progress.", details: nil))
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "Arguments must be a map.", details: nil))
      return
    }

    let rawSourcePath = (args["sourcePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !rawSourcePath.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Missing sourcePath.", details: nil))
      return
    }

    let sourceURL = URL(fileURLWithPath: rawSourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(FlutterError(code: "not_found", message: "Source file does not exist.", details: nil))
      return
    }

    guard let presenter = topViewController(from: presentingViewController) else {
      result(FlutterError(code: "unavailable", message: "Unable to present document picker.", details: nil))
      return
    }

    pendingResult = result

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
      } else {
        picker = UIDocumentPickerViewController(url: sourceURL, in: .exportToService)
      }

      picker.delegate = self
      picker.modalPresentationStyle = .formSheet
      if let popover = picker.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }

      presenter.present(picker, animated: true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: false)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(with: !urls.isEmpty)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
    finish(with: true)
  }

  private func finish(with value: Bool) {
    let result = pendingResult
    pendingResult = nil
    result?(value)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let navigation = controller as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = controller as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }
    return controller
  }
}

private final class FileSystemHandler: NSObject, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?
  private var pendingPickDirectory = false
  private let bookmarkKey = "file_system_bookmarks_v1"
  private let maxReadBytes = 100 * 1024
  private let maxBookmarkCount = 50

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = (call.arguments as? [String: Any]) ?? [:]
    switch call.method {
    case "pick_file":
      pick(directory: false, result: result)
    case "pick_directory":
      pick(directory: true, result: result)
    case "read":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.read(args: args) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "write":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.write(args: args, append: false) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "append":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.write(args: args, append: true) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "delete":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.delete(args: args) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "copy":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.transfer(args: args, isMove: false) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "move":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.transfer(args: args, isMove: true) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "revoke":
      let path = (args["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      var registry = loadBookmarks()
      let removed = registry.removeValue(forKey: path) != nil
      if removed {
        UserDefaults.standard.set(registry, forKey: bookmarkKey)
      }
      result(payload(["revoked": removed, "path": path]))
    case "list_bookmarks":
      let registry = loadBookmarks()
      let list = registry.keys.sorted().map { path -> [String: Any] in
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return [
          "path": path,
          "name": URL(fileURLWithPath: path).lastPathComponent,
          "is_directory": isDir.boolValue,
          "exists": exists,
        ]
      }
      result(payload(["bookmarks": list, "count": list.count]))
    case "stat":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.stat(args: args) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "list":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.list(args: args) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    case "mkdir":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let out = self?.mkdir(args: args) ?? ["success": false, "error": "deallocated"]
        DispatchQueue.main.async { result(out) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pick(directory: Bool, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(errorPayload("busy", "Another document picker is already active."))
      return
    }
    pendingResult = result
    pendingPickDirectory = directory
    let contentType: UTType = directory ? .folder : .item
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [contentType], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    topViewController(from: activeRootViewController())?.present(picker, animated: true)
  }

  private func activeRootViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first(where: { $0.activationState == .foregroundActive })?
      .windows.first(where: { $0.isKeyWindow })?
      .rootViewController
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPick(errorPayload("cancelled", "The user cancelled the document picker."))
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      finishPick(errorPayload("not_found", "No file was selected."))
      return
    }
    do {
      let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      saveBookmark(path: url.path, bookmarkBase64: bookmark.base64EncodedString())
      finishPick(payload([
        "path": url.path,
        "url": url.absoluteString,
        "name": url.lastPathComponent,
        "scope": pendingPickDirectory ? "directory" : "file",
      ]))
    } catch {
      finishPick(errorPayload("bookmark_failed", "Failed to save security-scoped bookmark: \(error.localizedDescription)"))
    }
  }

  private func read(args: [String: Any]) -> [String: Any] {
    let encoding = ((args["encoding"] as? String) ?? "utf8").lowercased()
    let offset = max(intArg(args["offset"]) ?? 0, 0)
    let length = min(max(intArg(args["length"]) ?? maxReadBytes, 1), maxReadBytes)
    return accessPath(args["path"]) { url in
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return errorPayload("not_found", "File does not exist.") }
      guard !isDir.boolValue else { return errorPayload("is_directory", "Path is a directory.") }
      if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
         values.isUbiquitousItem == true,
         values.ubiquitousItemDownloadingStatus == .notDownloaded {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return errorPayload("file_not_downloaded", "The file is stored in iCloud and has not been downloaded to the device yet. Download has been triggered. Please wait a moment and try again.")
      }
      do {
        let data = try Data(contentsOf: url)
        guard offset <= data.count else { return errorPayload("invalid_range", "offset is beyond end of file.") }
        let end = min(offset + length, data.count)
        let slice = data.subdata(in: offset..<end)
        let hasMore = end < data.count
        var res: [String: Any] = [
          "path": url.path,
          "bytes": slice.count,
          "total_bytes": data.count,
          "offset": offset,
          "has_more": hasMore,
        ]
        if hasMore {
          res["next_offset"] = end
        }
        if encoding == "base64" {
          res["encoding"] = "base64"
          res["base64"] = slice.base64EncodedString()
          return payload(res)
        }
        guard let text = String(data: slice, encoding: .utf8) else { return errorPayload("encoding_error", "File content is not valid UTF-8. Retry with encoding=base64.") }
        res["encoding"] = "utf8"
        res["content"] = text
        return payload(res)
      } catch {
        return errorPayload("read_failed", error.localizedDescription)
      }
    }
  }

  private func write(args: [String: Any], append: Bool) -> [String: Any] {
    return accessPath(args["path"], write: true) { url in
      let overwrite = boolArg(args["overwrite"]) ?? false
      let bytes: Data?
      if let b64 = args["base64"] as? String {
        bytes = Data(base64Encoded: b64)
      } else if let content = args["content"] as? String {
        bytes = content.data(using: .utf8)
      } else {
        return errorPayload("invalid_parameters", "Provide content or base64.")
      }
      guard let data = bytes else { return errorPayload("encoding_error", "Could not decode write content.") }
      do {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if append {
          if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
          } else {
            try data.write(to: url, options: .atomic)
          }
        } else {
          if FileManager.default.fileExists(atPath: url.path), !overwrite {
            return errorPayload("already_exists", "File already exists. Set overwrite=true to replace it.")
          }
          try data.write(to: url, options: .atomic)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let totalBytes = values?.fileSize ?? data.count
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        return payload([
          "path": url.path,
          "bytes": data.count,
          "total_bytes": totalBytes,
          "modified": modified,
        ])
      } catch {
        return errorPayload("write_failed", error.localizedDescription)
      }
    }
  }

  private func stat(args: [String: Any]) -> [String: Any] {
    accessPath(args["path"]) { url in
      do {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        return payload(["path": url.path, "name": url.lastPathComponent, "is_directory": values.isDirectory ?? false, "size": values.fileSize ?? 0, "modified": values.contentModificationDate?.timeIntervalSince1970 ?? 0])
      } catch {
        return errorPayload("not_found", error.localizedDescription)
      }
    }
  }

  private func list(args: [String: Any]) -> [String: Any] {
    accessPath(args["path"]) { url in
      do {
        let allUrls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
        let totalCount = allUrls.count
        let offset = max(intArg(args["offset"]) ?? 0, 0)
        let limit = min(max(intArg(args["limit"]) ?? 100, 1), 500)

        let pagedUrls: [URL]
        if offset >= totalCount {
          pagedUrls = []
        } else {
          let end = min(offset + limit, totalCount)
          pagedUrls = Array(allUrls[offset..<end])
        }

        let items = pagedUrls.map { child -> [String: Any] in
          let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
          return ["name": child.lastPathComponent, "path": child.path, "is_directory": values?.isDirectory ?? false, "size": values?.fileSize ?? 0]
        }
        let hasMore = (offset + items.count) < totalCount
        var res: [String: Any] = [
          "path": url.path,
          "count": items.count,
          "total_count": totalCount,
          "offset": offset,
          "limit": limit,
          "has_more": hasMore,
          "items": items,
        ]
        if hasMore {
          res["next_offset"] = offset + items.count
        }
        return payload(res)
      } catch {
        return errorPayload("not_directory", error.localizedDescription)
      }
    }
  }

  private func mkdir(args: [String: Any]) -> [String: Any] {
    accessPath(args["path"], write: true) { url in
      do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: boolArg(args["recursive"]) ?? true)
        return payload(["path": url.path])
      } catch {
        return errorPayload("write_failed", error.localizedDescription)
      }
    }
  }

  private func delete(args: [String: Any]) -> [String: Any] {
    accessPath(args["path"], write: true) { url in
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
        return errorPayload("not_found", "File or directory does not exist.")
      }
      if isDir.boolValue {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        if !items.isEmpty {
          return errorPayload("not_empty", "Directory is not empty. Recursive deletion is prohibited for safety.")
        }
      }
      do {
        try FileManager.default.removeItem(at: url)
        var registry = loadBookmarks()
        if registry.removeValue(forKey: url.path) != nil {
          UserDefaults.standard.set(registry, forKey: bookmarkKey)
        }
        return payload(["path": url.path, "deleted": true])
      } catch {
        return errorPayload("delete_failed", error.localizedDescription)
      }
    }
  }

  private func transfer(args: [String: Any], isMove: Bool) -> [String: Any] {
    let srcRaw = args["path"] ?? args["from_path"] ?? args["source"]
    let dstRaw = args["destination"] ?? args["to_path"] ?? args["dst"]
    let overwrite = boolArg(args["overwrite"]) ?? false

    guard normalizeUrl(srcRaw) != nil else {
      return errorPayload("invalid_parameters", "Source path is required.")
    }
    guard normalizeUrl(dstRaw) != nil else {
      return errorPayload("invalid_parameters", "Destination path is required.")
    }

    return accessPath(srcRaw, write: isMove) { srcUrl in
      return accessPath(dstRaw, write: true) { dstUrl in
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: srcUrl.path, isDirectory: &isDir) else {
          return errorPayload("not_found", "Source file or directory does not exist.")
        }
        if FileManager.default.fileExists(atPath: dstUrl.path) {
          if !overwrite {
            return errorPayload("already_exists", "Destination already exists. Set overwrite=true to replace it.")
          }
          do {
            try FileManager.default.removeItem(at: dstUrl)
          } catch {
            return errorPayload("overwrite_failed", "Failed to remove existing destination: \(error.localizedDescription)")
          }
        }
        do {
          let parent = dstUrl.deletingLastPathComponent()
          try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
          if isMove {
            try FileManager.default.moveItem(at: srcUrl, to: dstUrl)
            var registry = loadBookmarks()
            if let oldBookmark = registry.removeValue(forKey: srcUrl.path) {
              registry[dstUrl.path] = oldBookmark
              UserDefaults.standard.set(registry, forKey: bookmarkKey)
            }
          } else {
            try FileManager.default.copyItem(at: srcUrl, to: dstUrl)
          }
          return payload([
            "path": srcUrl.path,
            "destination": dstUrl.path,
            "is_move": isMove,
            "success": true,
          ])
        } catch {
          let op = isMove ? "move" : "copy"
          return errorPayload("\(op)_failed", error.localizedDescription)
        }
      }
    }
  }

  private func accessPath(_ raw: Any?, write: Bool = false, body: (URL) -> [String: Any]) -> [String: Any] {
    guard let url = normalizeUrl(raw), url.isFileURL else { return errorPayload("invalid_path", "A valid local file path is required.") }
    guard url.pathComponents.contains("..") == false else { return errorPayload("invalid_path", "Path traversal is not allowed.") }
    var bookmarks = loadBookmarks()
    var stale = false
    var scopeUrl: URL?
    var matchedRootPath: String?
    for (rootPath, encoded) in bookmarks where url.path == rootPath || url.path.hasPrefix(rootPath + "/") {
      if let data = Data(base64Encoded: encoded),
         let resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
        if stale {
          if let newBookmark = try? resolved.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[rootPath] = newBookmark.base64EncodedString()
            UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
          }
        }
        scopeUrl = resolved
        matchedRootPath = rootPath
        break
      } else if !FileManager.default.fileExists(atPath: rootPath) {
        // Auto-heal stale/deleted bookmark
        bookmarks.removeValue(forKey: rootPath)
        UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
      }
    }
    guard scopeUrl != nil || isAppSandboxPath(url) else {
      return errorPayload("permission_denied", "Path is not in the app sandbox and has not been authorized. Use pick_file or pick_directory first.")
    }
    let targetUrl: URL
    if let scope = scopeUrl {
      if url.path == scope.path {
        targetUrl = scope
      } else if let root = matchedRootPath, url.path.hasPrefix(root + "/") {
        let relative = String(url.path.dropFirst((root + "/").count))
        targetUrl = scope.appendingPathComponent(relative)
      } else {
        targetUrl = url
      }
    } else {
      targetUrl = url
    }
    if write && scopeUrl == nil {
      guard isWritableSandboxPath(targetUrl) else {
        return errorPayload("permission_denied", "Writing to sensitive app system directories (e.g. Library/Preferences) is prohibited. Only Documents and tmp are writable.")
      }
    }
    let accessed = scopeUrl?.startAccessingSecurityScopedResource() ?? false
    defer { if accessed { scopeUrl?.stopAccessingSecurityScopedResource() } }
    return body(targetUrl)
  }

  private func isAppSandboxPath(_ url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
    return path == home || path.hasPrefix(home + "/") || path == tmp || path.hasPrefix(tmp + "/")
  }

  private func isWritableSandboxPath(_ url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.standardizedFileURL.path ?? (URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents").standardizedFileURL.path)
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.standardizedFileURL.path ?? ""

    if path == docs || path.hasPrefix(docs + "/") { return true }
    if path == tmp || path.hasPrefix(tmp + "/") { return true }
    if !caches.isEmpty && (path == caches || path.hasPrefix(caches + "/")) { return true }
    return false
  }

  private func normalizeUrl(_ raw: Any?) -> URL? {
    guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    if text.hasPrefix("file://") { return URL(string: text) }
    return URL(fileURLWithPath: text)
  }

  private func loadBookmarks() -> [String: String] {
    (UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: String]) ?? [:]
  }

  private func saveBookmark(path: String, bookmarkBase64: String) {
    var registry = loadBookmarks()
    registry[path] = bookmarkBase64
    if registry.count > maxBookmarkCount {
      let excess = registry.count - maxBookmarkCount
      for _ in 0..<excess {
        if let firstKey = registry.keys.first {
          registry.removeValue(forKey: firstKey)
        }
      }
    }
    UserDefaults.standard.set(registry, forKey: bookmarkKey)
  }

  private func finishPick(_ value: [String: Any]) {
    let result = pendingResult
    pendingResult = nil
    result?(value)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let navigation = controller as? UINavigationController { return topViewController(from: navigation.visibleViewController) }
    if let tab = controller as? UITabBarController { return topViewController(from: tab.selectedViewController) }
    if let presented = controller?.presentedViewController { return topViewController(from: presented) }
    return controller
  }

  private func intArg(_ value: Any?) -> Int? {
    if let number = value as? Int { return number }
    if let number = value as? Double { return Int(number) }
    if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
    return nil
  }

  private func boolArg(_ value: Any?) -> Bool? {
    if let flag = value as? Bool { return flag }
    if let text = (value as? String)?.lowercased() {
      if text == "true" { return true }
      if text == "false" { return false }
    }
    return nil
  }

  private func payload(_ value: [String: Any]) -> [String: Any] {
    var out = value
    out["success"] = true
    return out
  }

  private func errorPayload(_ error: String, _ message: String) -> [String: Any] {
    ["success": false, "error": error, "message": message]
  }
}
 
 /// Native backend for the AI assistant's device-local tools on iOS.
 ///
 /// Calendar query/create is implemented with EventKit. Screen time has no
 /// generally available query API on iOS (the Screen Time frameworks require a
 /// special Family Controls entitlement), so it is not exposed here; the Dart
 /// side never offers that tool on iOS.
 ///
 /// Methods receive the tool arguments as a JSON string and return a JSON
 /// string payload. Errors the LLM should see (missing permission, bad
 /// arguments) are returned as JSON payloads with an "error" field.
 private final class DeviceLocalToolsHandler {
   private let eventStore = EKEventStore()
 
   func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
     let args = Self.parseArgs(call.arguments)
     switch call.method {
     case "hasUsageStatsPermission":
       result(false)
     case "openUsageAccessSettings":
       result(nil)
     case "hasCalendarPermission":
       result(hasCalendarPermission())
     case "requestCalendarPermission":
       requestCalendarPermission(result: result)
     case "queryCalendar":
       ensureCalendarAccess { [weak self] granted in
         guard let self else { return }
         guard granted else {
           result(Self.noPermissionPayload)
           return
         }
         DispatchQueue.global(qos: .userInitiated).async {
           let payload = self.queryCalendar(args: args)
           DispatchQueue.main.async { result(payload) }
         }
       }
     case "createCalendarEvent":
       ensureCalendarAccess { [weak self] granted in
         guard let self else { return }
         guard granted else {
           result(Self.noPermissionPayload)
           return
         }
         DispatchQueue.global(qos: .userInitiated).async {
           let payload = self.createCalendarEvent(args: args)
           DispatchQueue.main.async { result(payload) }
         }
       }
     case "getScreenTime":
       result(Self.errorPayload(
         "UNSUPPORTED_PLATFORM",
         "Screen time queries are not available on iOS; Apple does not provide a general-purpose API for this."
       ))
     default:
       result(FlutterMethodNotImplemented)
     }
   }
 
   // MARK: - Permission
 
   private static let noPermissionPayload = errorPayload(
     "NO_PERMISSION",
     "Calendar permission is not granted. Please ask the user to allow full calendar access "
       + "for this app in the system Settings and try again."
   )

   private func hasCalendarPermission() -> Bool {
     let status = EKEventStore.authorizationStatus(for: .event)
     if #available(iOS 17.0, *) {
       return status == .fullAccess
     }
     return status == .authorized
   }

   /// Used by the assistant settings toggle. Prompts when undetermined; opens
   /// Settings when previously denied/restricted/write-only.
   private func requestCalendarPermission(result: @escaping FlutterResult) {
     let finish: (Bool) -> Void = { granted in
       DispatchQueue.main.async { result(granted) }
     }
     let status = EKEventStore.authorizationStatus(for: .event)
     if #available(iOS 17.0, *) {
       switch status {
       case .fullAccess:
         finish(true)
       case .notDetermined:
         eventStore.requestFullAccessToEvents { granted, _ in finish(granted) }
       default:
         openAppSettings()
         finish(false)
       }
     } else {
       switch status {
       case .authorized:
         finish(true)
       case .notDetermined:
         eventStore.requestAccess(to: .event) { granted, _ in finish(granted) }
       default:
         openAppSettings()
         finish(false)
       }
     }
   }

   private func openAppSettings() {
     guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
     UIApplication.shared.open(url)
   }
 
   private func ensureCalendarAccess(completion: @escaping (Bool) -> Void) {
     let finish: (Bool) -> Void = { granted in
       DispatchQueue.main.async { completion(granted) }
     }
     let status = EKEventStore.authorizationStatus(for: .event)
     if #available(iOS 17.0, *) {
       switch status {
       case .fullAccess:
         finish(true)
       case .notDetermined:
         eventStore.requestFullAccessToEvents { granted, _ in finish(granted) }
       default:
         finish(false)
       }
     } else {
       switch status {
       case .authorized:
         finish(true)
       case .notDetermined:
         eventStore.requestAccess(to: .event) { granted, _ in finish(granted) }
       default:
         finish(false)
       }
     }
   }
 
   // MARK: - Calendar query
 
   private func queryCalendar(args: [String: Any]) -> String {
     let limit = min(max(Self.intArg(args["limit"]) ?? 20, 1), 100)
     let keyword = (args["query"] as? String)?
       .trimmingCharacters(in: .whitespacesAndNewlines)
       .lowercased()
     let rangePreset = (args["range"] as? String)?.lowercased() ?? "today"
 
     // ISO 8601 calendar so week presets start on Monday, matching Android.
     var calendar = Calendar(identifier: .iso8601)
     calendar.timeZone = .current
     let now = Date()
     let startOfToday = calendar.startOfDay(for: now)
 
     let startDate: Date
     let endDate: Date
     if let beginRaw = args["begin"] as? String, !beginRaw.isEmpty {
       guard let parsedStart = Self.parseTime(beginRaw, calendar: calendar) else {
         return Self.invalidTimePayload(beginRaw)
       }
       startDate = parsedStart
       if let endRaw = args["end"] as? String, !endRaw.isEmpty {
         guard let parsedEnd = Self.parseTime(endRaw, calendar: calendar) else {
           return Self.invalidTimePayload(endRaw)
         }
         endDate = parsedEnd
       } else {
         endDate = now
       }
     } else {
       switch rangePreset {
       case "week":
         let weekStart = calendar.date(
           from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
         ) ?? startOfToday
         startDate = weekStart
         endDate = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
       case "month":
         let monthStart = calendar.date(
           from: calendar.dateComponents([.year, .month], from: now)
         ) ?? startOfToday
         startDate = monthStart
         endDate = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
       default:
         startDate = startOfToday
         endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
       }
     }
 
     guard startDate < endDate else {
       return Self.errorPayload("INVALID_RANGE", "begin must be earlier than end.")
     }
 
     let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
     var events = eventStore.events(matching: predicate)
     if let keyword, !keyword.isEmpty {
       events = events.filter { ($0.title ?? "").lowercased().contains(keyword) }
     }
     events.sort { $0.startDate < $1.startDate }
 
     var items: [[String: Any]] = []
     for event in events.prefix(limit) {
       var item: [String: Any] = [
         "id": event.eventIdentifier ?? "",
         "title": event.title ?? "",
         "description": event.notes ?? "",
         "location": event.location ?? "",
         "all_day": event.isAllDay,
         "calendar": event.calendar?.title ?? "",
       ]
       if event.isAllDay {
         item["start"] = Self.formatDateOnly(event.startDate, calendar: calendar)
         // Report the exclusive end date (tool convention, matches Android);
         // EventKit stores all-day ends inside the last included day.
         item["end"] = event.endDate.map {
           Self.formatDateOnly(Self.exclusiveAllDayEnd($0, calendar: calendar), calendar: calendar)
         } ?? ""
       } else {
         item["start"] = Self.formatDateTime(event.startDate)
         item["end"] = event.endDate.map(Self.formatDateTime) ?? ""
       }
       items.append(item)
     }
 
     return Self.jsonString([
       "range_start": Self.formatDateTime(startDate),
       "range_end": Self.formatDateTime(endDate),
       "count": items.count,
       "events": items,
     ])
   }
 
   // MARK: - Calendar create
 
   private func createCalendarEvent(args: [String: Any]) -> String {
     let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
     let startRaw = (args["start"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
     guard !title.isEmpty, !startRaw.isEmpty else {
       return Self.errorPayload("MISSING_REQUIRED", "Both 'title' and 'start' are required.")
     }
     let allDay = Self.boolArg(args["all_day"]) ?? false
 
     var calendar = Calendar(identifier: .iso8601)
     calendar.timeZone = .current
 
     guard let startDate = Self.parseTime(startRaw, calendar: calendar) else {
       return Self.invalidTimePayload(startRaw)
     }
     let endDate: Date
     if let endRaw = args["end"] as? String, !endRaw.isEmpty {
       guard let parsedEnd = Self.parseTime(endRaw, calendar: calendar) else {
         return Self.invalidTimePayload(endRaw)
       }
       endDate = parsedEnd
     } else if allDay {
       let dayStart = calendar.startOfDay(for: startDate)
       endDate = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? startDate.addingTimeInterval(86400)
     } else {
       endDate = startDate.addingTimeInterval(3600)
     }
     guard startDate < endDate else {
       return Self.errorPayload("INVALID_RANGE", "end must be later than start.")
     }
 
     // For all-day events, normalize both ends to day boundaries first (like
     // Android's LocalDate comparison), so e.g. a 12:00-18:00 same-day range is
     // rejected instead of silently producing a degenerate event.
     let allDayStart = calendar.startOfDay(for: startDate)
     let allDayEndExclusive = calendar.startOfDay(for: endDate)
     if allDay, allDayStart >= allDayEndExclusive {
       return Self.errorPayload("INVALID_RANGE", "all-day event end date must be later than start date.")
     }
 
     guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
       return Self.errorPayload(
         "NO_CALENDAR",
         "No calendar account found on this device. Please add a calendar account first."
       )
     }
 
     let event = EKEvent(eventStore: eventStore)
     event.calendar = targetCalendar
     event.title = title
     if let notes = args["description"] as? String, !notes.isEmpty {
       event.notes = notes
     }
     if let location = args["location"] as? String, !location.isEmpty {
       event.location = location
     }
     if allDay {
       event.isAllDay = true
       event.startDate = allDayStart
       // The tool's 'end' is exclusive (next-day midnight); EventKit treats the
       // end date's day as included, so step back one second to avoid spilling
       // into an extra day. Payloads convert back to the exclusive date.
       event.endDate = allDayEndExclusive.addingTimeInterval(-1)
     } else {
       event.startDate = startDate
       event.endDate = endDate
     }
 
     // Reminders are minutes before the event start; EKAlarm takes a negative
     // offset in seconds relative to the start date.
     let reminderMinutes = Self.reminderMinutesArg(args["reminders"])
     for minutes in reminderMinutes {
       event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
     }
 
     do {
       try eventStore.save(event, span: .thisEvent, commit: true)
     } catch {
       return Self.errorPayload("INSERT_FAILED", "Failed to save calendar event: \(error.localizedDescription)")
     }
 
     var payload: [String: Any] = [
       "success": true,
       "event_id": event.eventIdentifier ?? "",
       "title": title,
       "all_day": allDay,
       "location": event.location ?? "",
       "reminders": reminderMinutes,
     ]
     if allDay {
       payload["start"] = Self.formatDateOnly(allDayStart, calendar: calendar)
       payload["end"] = Self.formatDateOnly(allDayEndExclusive, calendar: calendar)
     } else {
       payload["start"] = Self.formatDateTime(startDate)
       payload["end"] = Self.formatDateTime(endDate)
     }
     return Self.jsonString(payload)
   }
 
   // MARK: - Argument/JSON helpers
 
   private static func parseArgs(_ arguments: Any?) -> [String: Any] {
     guard
       let json = arguments as? String,
       let data = json.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
     else {
       return [:]
     }
     return parsed
   }
 
   private static func intArg(_ value: Any?) -> Int? {
     if let number = value as? Int { return number }
     if let number = value as? Double { return Int(number) }
     if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
     return nil
   }
 
   /// Reminder offsets in minutes before the event start. Accepts a JSON array,
   /// or a single number/string for convenience. Negative values (models
   /// sometimes send "-10" for "10 minutes before") are folded to positive;
   /// duplicates are dropped and at most 5 are kept, matching EventKit's
   /// practical limit for well-behaved events.
   private static func reminderMinutesArg(_ value: Any?) -> [Int] {
     let raw: [Any]
     if let list = value as? [Any] {
       raw = list
     } else if let value, !(value is NSNull) {
       raw = [value]
     } else {
       return []
     }
     var seen = Set<Int>()
     var minutes: [Int] = []
     for item in raw {
       guard let normalized = clampedMinutes(item) else { continue }
       if seen.insert(normalized).inserted {
         minutes.append(normalized)
       }
       if minutes.count == 5 { break }
     }
     return minutes
   }
 
   /// Clamps one reminder offset into 0...40320 minutes (4 weeks). Parsed as a
   /// Double throughout: an out-of-range or Int.min value would trap on the
   /// Int conversion, and these values come straight from model output.
   private static func clampedMinutes(_ value: Any?) -> Int? {
     let raw: Double
     if let number = value as? NSNumber {
       raw = number.doubleValue
     } else if let text = (value as? String)?.trimmingCharacters(in: .whitespaces),
               let parsed = Double(text) {
       raw = parsed
     } else {
       return nil
     }
     guard raw.isFinite else { return nil }
     return Int(min(abs(raw), 40320))
   }
 
   private static func boolArg(_ value: Any?) -> Bool? {
     if let flag = value as? Bool { return flag }
     if let text = (value as? String)?.lowercased() {
       if text == "true" { return true }
       if text == "false" { return false }
     }
     return nil
   }
 
   private static func jsonString(_ payload: [String: Any]) -> String {
     guard
       let data = try? JSONSerialization.data(withJSONObject: payload),
       let text = String(data: data, encoding: .utf8)
     else {
       return "{\"error\":\"ENCODING_ERROR\",\"message\":\"Failed to encode tool result.\"}"
     }
     return text
   }
 
   private static func errorPayload(_ error: String, _ message: String) -> String {
     jsonString(["error": error, "message": message])
   }
 
   private static func invalidTimePayload(_ raw: String) -> String {
     errorPayload(
       "INVALID_TIME",
       "Invalid time format: '\(raw)'. Use ISO-8601 date/date-time or epoch milliseconds."
     )
   }
 
   // MARK: - Time parsing/formatting
 
   /// Parses epoch milliseconds, offset date-times, local date-times, and
   /// plain dates (interpreted at local midnight), mirroring the Android tool.
   private static func parseTime(_ raw: String, calendar: Calendar) -> Date? {
     let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
     if !text.isEmpty, text.allSatisfy({ $0.isNumber }), let millis = Double(text) {
       return Date(timeIntervalSince1970: millis / 1000.0)
     }
 
     let isoWithFraction = ISO8601DateFormatter()
     isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
     if let date = isoWithFraction.date(from: text) { return date }
 
     let iso = ISO8601DateFormatter()
     iso.formatOptions = [.withInternetDateTime]
     if let date = iso.date(from: text) { return date }
 
     for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
       let formatter = DateFormatter()
       formatter.locale = Locale(identifier: "en_US_POSIX")
       formatter.timeZone = calendar.timeZone
       formatter.dateFormat = format
       if let date = formatter.date(from: text) { return date }
     }
     return nil
   }
 
   private static func formatDateTime(_ date: Date) -> String {
     let formatter = ISO8601DateFormatter()
     formatter.formatOptions = [.withInternetDateTime]
     formatter.timeZone = .current
     return formatter.string(from: date)
   }
 
   private static func formatDateOnly(_ date: Date, calendar: Calendar) -> String {
     let formatter = DateFormatter()
     formatter.locale = Locale(identifier: "en_US_POSIX")
     formatter.timeZone = calendar.timeZone
     formatter.dateFormat = "yyyy-MM-dd"
     return formatter.string(from: date)
   }
 
   /// Converts a stored all-day end date to the tool's exclusive end date.
   /// EventKit keeps the end inside the last included day (e.g. 23:59:59),
   /// while the tool reports the next-day midnight boundary. Ends already at
   /// an exact midnight are treated as exclusive and returned unchanged.
   private static func exclusiveAllDayEnd(_ end: Date, calendar: Calendar) -> Date {
     calendar.startOfDay(for: end.addingTimeInterval(1))
   }
 }
