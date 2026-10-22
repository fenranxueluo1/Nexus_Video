import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var mediaChannel: FlutterMethodChannel?
  private var platformChannel: FlutterMethodChannel?
  private var documentController: UIDocumentInteractionController?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NexusChannels"
    ) else {
      return
    }
    let messenger = registrar.messenger()

    let media = FlutterMethodChannel(
      name: "nexus/media_packager",
      binaryMessenger: messenger
    )
    media.setMethodCallHandler { [weak self] call, result in
      self?.handleMediaCall(call, result: result)
    }
    mediaChannel = media

    let platform = FlutterMethodChannel(
      name: "nexus/platform",
      binaryMessenger: messenger
    )
    platform.setMethodCallHandler { [weak self] call, result in
      self?.handlePlatformCall(call, result: result)
    }
    platformChannel = platform
  }

  private func handlePlatformCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "openFile":
      guard let path = arguments?["path"] as? String, !path.isEmpty else {
        result(false)
        return
      }
      result(openFile(path))
    case "openUrl":
      guard let url = arguments?["url"] as? String, !url.isEmpty else {
        result(false)
        return
      }
      result(openUrl(url))
    case "copyFolderToDownloads":
      guard let path = arguments?["path"] as? String, !path.isEmpty else {
        result(0)
        return
      }
      result(exportFiles(path))
    case "openFolder":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openFile(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      return false
    }
    guard let presenter = topViewController() else {
      return false
    }
    let controller = UIDocumentInteractionController(
      url: URL(fileURLWithPath: path)
    )
    controller.delegate = self
    documentController = controller
    return controller.presentOptionsMenu(
      from: presenter.view.bounds,
      in: presenter.view,
      animated: true
    )
  }

  private func openUrl(_ string: String) -> Bool {
    guard let url = URL(string: string) else {
      return false
    }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return true
  }

  private func exportFiles(_ path: String) -> Int {
    let source = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return 0
    }
    var urls: [URL] = []
    if isDirectory.boolValue {
      if let enumerator = FileManager.default.enumerator(
        at: source,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) {
        while let fileURL = enumerator.nextObject() as? URL {
          if let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey]
          ),
             values.isRegularFile == true {
            urls.append(fileURL)
          }
        }
      }
    } else {
      urls.append(source)
    }
    guard !urls.isEmpty, let presenter = topViewController() else {
      return 0
    }
    let picker = UIDocumentPickerViewController(
      forExporting: urls,
      asCopy: true
    )
    picker.modalPresentationStyle = .formSheet
    presenter.present(picker, animated: true)
    return urls.count
  }

  fileprivate func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func handleMediaCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard call.method == "mux" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let outputPath = arguments["outputPath"] as? String,
          !outputPath.isEmpty else {
      result(FlutterError(code: "bad_arguments", message: "缺少输出路径", details: nil))
      return
    }
    let videoPath = (arguments["videoPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let audioPath = (arguments["audioPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let dropAudio = arguments["dropAudio"] as? Bool ?? false
    guard videoPath != nil || audioPath != nil else {
      result(FlutterError(code: "bad_arguments", message: "没有可合并的音视频流", details: nil))
      return
    }
    mux(
      videoPath: videoPath,
      audioPath: audioPath,
      dropAudio: dropAudio,
      outputPath: outputPath,
      result: result
    )
  }

  private func mux(
    videoPath: String?,
    audioPath: String?,
    dropAudio: Bool,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let composition = AVMutableComposition()
        var hasVideo = false
        var hasAudio = false

        if let videoPath = videoPath {
          let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
          let duration = asset.duration
          if let track = asset.tracks(withMediaType: .video).first,
             let compositionTrack = composition.addMutableTrack(
               withMediaType: .video,
               preferredTrackID: kCMPersistentTrackID_Invalid
             ) {
            try compositionTrack.insertTimeRange(
              CMTimeRange(start: .zero, duration: duration),
              of: track,
              at: .zero
            )
            compositionTrack.preferredTransform = track.preferredTransform
            hasVideo = true
          }
          if audioPath == nil && !dropAudio,
             let track = asset.tracks(withMediaType: .audio).first,
             let compositionTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
             ) {
            try compositionTrack.insertTimeRange(
              CMTimeRange(start: .zero, duration: duration),
              of: track,
              at: .zero
            )
            hasAudio = true
          }
        }

        if let audioPath = audioPath {
          let asset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
          let duration = asset.duration
          if let track = asset.tracks(withMediaType: .audio).first,
             let compositionTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
             ) {
            try compositionTrack.insertTimeRange(
              CMTimeRange(start: .zero, duration: duration),
              of: track,
              at: .zero
            )
            hasAudio = true
          }
        }

        guard hasVideo || hasAudio else {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "no_tracks",
                message: "输入文件没有可用的音视频轨道",
                details: nil
              )
            )
          }
          return
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: outputURL)
        let audioOnly = !hasVideo && hasAudio
        let preset = audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetPassthrough
        guard let export = AVAssetExportSession(
          asset: composition,
          presetName: preset
        ) else {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "export_init",
                message: "无法创建媒体导出会话",
                details: nil
              )
            )
          }
          return
        }
        export.outputURL = outputURL
        export.outputFileType = outputURL.pathExtension.lowercased() == "m4a" ? AVFileType.m4a : AVFileType.mp4
        export.shouldOptimizeForNetworkUse = true
        export.exportAsynchronously {
          DispatchQueue.main.async {
            switch export.status {
            case .completed:
              if let attributes = try? FileManager.default.attributesOfItem(
                atPath: outputPath
              ),
                 let size = attributes[.size] as? NSNumber,
                 size.intValue > 0 {
                result(nil)
              } else {
                result(
                  FlutterError(
                    code: "empty_output",
                    message: "媒体框架没有生成输出文件",
                    details: nil
                  )
                )
              }
            case .failed, .cancelled:
              result(
                FlutterError(
                  code: "export_failed",
                  message: export.error?.localizedDescription ?? "媒体合并失败",
                  details: nil
                )
              )
            default:
              result(
                FlutterError(
                  code: "export_failed",
                  message: "媒体合并未完成",
                  details: nil
                )
              )
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "mux_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }
}

extension AppDelegate: UIDocumentInteractionControllerDelegate {
  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    return topViewController() ?? UIViewController()
  }
}
