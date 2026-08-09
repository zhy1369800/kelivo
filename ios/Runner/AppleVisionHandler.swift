import Foundation
import Vision
import CoreImage
import UIKit
import Flutter

final class AppleVisionHandler: NSObject {
  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "ocr", "recognizeText":
      recognizeText(args: args, result: result)
    case "detectBarcodes", "qrScan":
      detectBarcodes(args: args, result: result)
    case "detectFaces", "faceDetection":
      detectFaces(args: args, result: result)
    case "classifyImage", "imageClassification":
      classifyImage(args: args, result: result)
    case "analyzeAll":
      analyzeAll(args: args, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Image Loader Helper

  private func loadCGImage(from path: String) -> CGImage? {
    let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanPath.isEmpty else { return nil }

    let fileUrl = URL(fileURLWithPath: cleanPath)
    if let ciImage = CIImage(contentsOf: fileUrl) {
      let context = CIContext()
      if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
        return cgImage
      }
    }
    if let uiImage = UIImage(contentsOfFile: cleanPath), let cgImage = uiImage.cgImage {
      return cgImage
    }
    return nil
  }

  private func formatBoundingBox(_ rect: CGRect) -> [String: Double] {
    return [
      "x": (rect.origin.x * 10000).rounded() / 10000,
      "y": (rect.origin.y * 10000).rounded() / 10000,
      "width": (rect.size.width * 10000).rounded() / 10000,
      "height": (rect.size.height * 10000).rounded() / 10000
    ]
  }

  // MARK: - 1. OCR / Text Recognition

  private func recognizeText(args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["image_path"] as? String, let cgImage = loadCGImage(from: path) else {
      result(FlutterError(code: "invalid_image", message: "Valid 'image_path' is required.", details: nil))
      return
    }

    let languages = (args["languages"] as? [String]) ?? ["zh-Hans", "zh-Hant", "en-US"]
    let accurate = (args["accurate"] as? Bool) ?? true

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let observations = request.results as? [VNRecognizedTextObservation] else {
        DispatchQueue.main.async {
          result(["full_text": "", "line_count": 0, "lines": []])
        }
        return
      }

      var lines = [[String: Any]]()
      var fullTextLines = [String]()

      for obs in observations {
        if let topCandidate = obs.topCandidates(1).first {
          fullTextLines.append(topCandidate.string)
          lines.append([
            "text": topCandidate.string,
            "confidence": (topCandidate.confidence * 100).rounded() / 100,
            "bounding_box": self.formatBoundingBox(obs.boundingBox)
          ])
        }
      }

      let fullText = fullTextLines.joined(separator: "\n")
      DispatchQueue.main.async {
        result([
          "full_text": fullText,
          "line_count": lines.count,
          "lines": lines
        ])
      }
    }

    request.recognitionLevel = accurate ? .accurate : .fast
    request.usesLanguageCorrection = true
    if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = true
    }
    request.recognitionLanguages = languages

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - 2. Barcode / QR Code Detection

  private func detectBarcodes(args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["image_path"] as? String, let cgImage = loadCGImage(from: path) else {
      result(FlutterError(code: "invalid_image", message: "Valid 'image_path' is required.", details: nil))
      return
    }

    let request = VNDetectBarcodesRequest { request, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "barcode_detection_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let observations = request.results as? [VNBarcodeObservation] else {
        DispatchQueue.main.async {
          result(["count": 0, "barcodes": []])
        }
        return
      }

      var barcodes = [[String: Any]]()
      for obs in observations {
        let payload = obs.payloadStringValue ?? ""
        let symbology = obs.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
        barcodes.append([
          "payload": payload,
          "symbology": symbology,
          "bounding_box": self.formatBoundingBox(obs.boundingBox)
        ])
      }

      DispatchQueue.main.async {
        result([
          "count": barcodes.count,
          "barcodes": barcodes
        ])
      }
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "barcode_detection_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - 3. Face Detection

  private func detectFaces(args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["image_path"] as? String, let cgImage = loadCGImage(from: path) else {
      result(FlutterError(code: "invalid_image", message: "Valid 'image_path' is required.", details: nil))
      return
    }

    let includeLandmarks = (args["include_landmarks"] as? Bool) ?? false

    let completion: VNRequestCompletionHandler = { request, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "face_detection_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let observations = request.results as? [VNFaceObservation] else {
        DispatchQueue.main.async {
          result(["count": 0, "faces": []])
        }
        return
      }

      var faces = [[String: Any]]()
      for obs in observations {
        var faceInfo: [String: Any] = [
          "confidence": (obs.confidence * 100).rounded() / 100,
          "bounding_box": self.formatBoundingBox(obs.boundingBox)
        ]
        if let roll = obs.roll?.doubleValue {
          faceInfo["roll"] = (roll * 180 / .pi * 10).rounded() / 10
        }
        if let yaw = obs.yaw?.doubleValue {
          faceInfo["yaw"] = (yaw * 180 / .pi * 10).rounded() / 10
        }
        if includeLandmarks, let landmarks = obs.landmarks {
          var landmarkCount = 0
          if let eyes = landmarks.leftEye?.pointCount { landmarkCount += eyes }
          if let eyes = landmarks.rightEye?.pointCount { landmarkCount += eyes }
          if let nose = landmarks.nose?.pointCount { landmarkCount += nose }
          if let outerLips = landmarks.outerLips?.pointCount { landmarkCount += outerLips }
          faceInfo["landmark_points_count"] = landmarkCount
        }
        faces.append(faceInfo)
      }

      DispatchQueue.main.async {
        result([
          "count": faces.count,
          "faces": faces
        ])
      }
    }

    let request: VNRequest
    if includeLandmarks {
      request = VNDetectFaceLandmarksRequest(completionHandler: completion)
    } else {
      request = VNDetectFaceRectanglesRequest(completionHandler: completion)
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "face_detection_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - 4. Image Classification

  private func classifyImage(args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["image_path"] as? String, let cgImage = loadCGImage(from: path) else {
      result(FlutterError(code: "invalid_image", message: "Valid 'image_path' is required.", details: nil))
      return
    }

    let maxResults = (args["max_results"] as? Int) ?? 10
    let minConfidence = (args["min_confidence"] as? Double) ?? 0.05

    let request = VNClassifyImageRequest { request, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "classification_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let observations = request.results as? [VNClassificationObservation] else {
        DispatchQueue.main.async {
          result(["count": 0, "categories": []])
        }
        return
      }

      var categories = [[String: Any]]()
      for obs in observations {
        if Double(obs.confidence) >= minConfidence {
          categories.append([
            "identifier": obs.identifier,
            "confidence": (obs.confidence * 100).rounded() / 100,
            "label": self.translateClassificationIdentifier(obs.identifier)
          ])
          if categories.count >= maxResults {
            break
          }
        }
      }

      DispatchQueue.main.async {
        result([
          "count": categories.count,
          "categories": categories
        ])
      }
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "classification_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - 5. Analyze All (Combined Analysis Pass)

  private func analyzeAll(args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["image_path"] as? String, let cgImage = loadCGImage(from: path) else {
      result(FlutterError(code: "invalid_image", message: "Valid 'image_path' is required.", details: nil))
      return
    }

    var textResult = [String: Any]()
    var barcodeResult = [String: Any]()
    var faceResult = [String: Any]()
    var classResult = [String: Any]()

    let group = DispatchGroup()

    // 1. Text Recognition
    group.enter()
    let textReq = VNRecognizeTextRequest { req, _ in
      defer { group.leave() }
      if let obs = req.results as? [VNRecognizedTextObservation] {
        var lines = [String]()
        for o in obs {
          if let c = o.topCandidates(1).first {
            lines.append(c.string)
          }
        }
        textResult = [
          "full_text": lines.joined(separator: "\n"),
          "line_count": lines.count
        ]
      }
    }
    textReq.recognitionLevel = .accurate
    textReq.usesLanguageCorrection = true

    // 2. Barcode Detection
    group.enter()
    let barcodeReq = VNDetectBarcodesRequest { req, _ in
      defer { group.leave() }
      if let obs = req.results as? [VNBarcodeObservation] {
        var barcodes = [[String: Any]]()
        for o in obs {
          barcodes.append([
            "payload": o.payloadStringValue ?? "",
            "symbology": o.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
          ])
        }
        barcodeResult = ["count": barcodes.count, "barcodes": barcodes]
      }
    }

    // 3. Face Detection
    group.enter()
    let faceReq = VNDetectFaceRectanglesRequest { req, _ in
      defer { group.leave() }
      if let obs = req.results as? [VNFaceObservation] {
        faceResult = ["count": obs.count]
      }
    }

    // 4. Classification
    group.enter()
    let classReq = VNClassifyImageRequest { req, _ in
      defer { group.leave() }
      if let obs = req.results as? [VNClassificationObservation] {
        var topTags = [String]()
        for o in obs.prefix(5) {
          if o.confidence > 0.1 {
            topTags.append(self.translateClassificationIdentifier(o.identifier))
          }
        }
        classResult = ["top_tags": topTags]
      }
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([textReq, barcodeReq, faceReq, classReq])
      } catch {
        // Ignore error
      }
      group.notify(queue: .main) {
        result([
          "success": true,
          "ocr": textResult,
          "barcodes": barcodeResult,
          "faces": faceResult,
          "classification": classResult
        ])
      }
    }
  }

  // MARK: - Classification Label Translator

  private func translateClassificationIdentifier(_ id: String) -> String {
    let clean = id.replacingOccurrences(of: "_", with: " ")
    return clean
  }
}
