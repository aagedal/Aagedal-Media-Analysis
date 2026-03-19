import Foundation
import Combine
import Vision
import AppKit

/// Face detection and clustering using Apple Vision framework
class FaceDetectionService: ObservableObject {

    @Published var isDetecting = false
    @Published var progress: Double = 0
    @Published var error: Error?

    struct DetectionConfig {
        var minConfidence: Float = 0.7
        var minFaceSize: CGFloat = 50
        var clusteringThreshold: Float = 0.55
    }

    var config = DetectionConfig()

    /// Detect faces in an image and return detected face data
    func detectFaces(in imageURL: URL) async throws -> [DetectedFace] {
        isDetecting = true
        progress = 0
        error = nil
        defer { isDetecting = false }

        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "FaceDetection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load image"])
        }

        let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
        let featurePrintRequest = VNGenerateImageFeaturePrintRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([faceLandmarksRequest, featurePrintRequest])

        guard let faceObservations = faceLandmarksRequest.results else { return [] }

        var faces: [DetectedFace] = []

        for observation in faceObservations {
            guard observation.confidence >= config.minConfidence else { continue }

            let boundingBox = observation.boundingBox
            let faceWidth = boundingBox.width * CGFloat(cgImage.width)
            guard faceWidth >= config.minFaceSize else { continue }

            // Generate feature print for this face region
            let faceImage = cropFace(from: cgImage, boundingBox: boundingBox)
            guard let faceImage else { continue }

            let faceHandler = VNImageRequestHandler(cgImage: faceImage, options: [:])
            let fpRequest = VNGenerateImageFeaturePrintRequest()
            try? faceHandler.perform([fpRequest])

            guard let featurePrint = fpRequest.results?.first,
                  let fpData = try? NSKeyedArchiver.archivedData(withRootObject: featurePrint, requiringSecureCoding: true) else {
                continue
            }

            // Generate thumbnail
            let thumbnailData = generateThumbnail(from: cgImage, boundingBox: boundingBox)

            var face = DetectedFace(
                featurePrintData: fpData,
                boundingBox: boundingBox,
                qualityScore: observation.confidence,
                confidence: observation.confidence
            )
            face.thumbnailData = thumbnailData
            faces.append(face)
        }

        progress = 1.0
        return faces
    }

    /// Cluster detected faces into groups
    func clusterFaces(_ faces: [DetectedFace]) -> [FaceGroup] {
        guard !faces.isEmpty else { return [] }

        // Simple greedy clustering based on feature print distance
        var groups: [FaceGroup] = []
        var assigned = Set<UUID>()

        for face in faces {
            guard !assigned.contains(face.id) else { continue }

            var group = [face]
            assigned.insert(face.id)

            for other in faces {
                guard !assigned.contains(other.id) else { continue }
                if let distance = computeDistance(face.featurePrintData, other.featurePrintData),
                   distance < config.clusteringThreshold {
                    group.append(other)
                    assigned.insert(other.id)
                }
            }

            groups.append(FaceGroup(faces: group))
        }

        return groups
    }

    // MARK: - Private Helpers

    private func cropFace(from image: CGImage, boundingBox: CGRect) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Expand bounding box slightly for better feature extraction
        let expandFactor: CGFloat = 0.3
        let x = max(0, (boundingBox.minX - expandFactor * boundingBox.width) * width)
        let y = max(0, (1 - boundingBox.maxY - expandFactor * boundingBox.height) * height)
        let w = min(width - x, (1 + 2 * expandFactor) * boundingBox.width * width)
        let h = min(height - y, (1 + 2 * expandFactor) * boundingBox.height * height)

        let rect = CGRect(x: x, y: y, width: w, height: h)
        return image.cropping(to: rect)
    }

    private func generateThumbnail(from image: CGImage, boundingBox: CGRect) -> Data? {
        guard let cropped = cropFace(from: image, boundingBox: boundingBox) else { return nil }
        let nsImage = NSImage(cgImage: cropped, size: NSSize(width: 120, height: 120))
        return nsImage.jpegData(compressionQuality: 0.7)
    }

    private func computeDistance(_ data1: Data, _ data2: Data) -> Float? {
        guard let fp1 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data1),
              let fp2 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data2) else {
            return nil
        }
        var distance: Float = 0
        try? fp1.computeDistance(&distance, to: fp2)
        return distance
    }
}
