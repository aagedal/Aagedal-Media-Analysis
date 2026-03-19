import Foundation
import CoreGraphics

struct CodableRect: Codable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }
}

struct DetectedFace: Codable, Identifiable, Sendable {
    let id: UUID
    var featurePrintData: Data
    var boundingBox: CodableRect
    var qualityScore: Float
    var confidence: Float
    var thumbnailData: Data?
    var personName: String?

    init(featurePrintData: Data, boundingBox: CGRect, qualityScore: Float, confidence: Float) {
        self.id = UUID()
        self.featurePrintData = featurePrintData
        self.boundingBox = CodableRect(boundingBox)
        self.qualityScore = qualityScore
        self.confidence = confidence
    }
}

struct FaceGroup: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String?
    var faces: [DetectedFace]
    var representativeFaceID: UUID?

    init(name: String? = nil, faces: [DetectedFace]) {
        self.id = UUID()
        self.name = name
        self.faces = faces
        self.representativeFaceID = faces.first?.id
    }
}

struct FileFaceData: Codable, Sendable {
    var fileName: String
    var groups: [FaceGroup]
    var detectedAt: Date

    init(fileName: String, groups: [FaceGroup]) {
        self.fileName = fileName
        self.groups = groups
        self.detectedAt = Date()
    }
}
