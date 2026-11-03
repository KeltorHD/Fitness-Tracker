import FitnessTrackerCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Re-encodes only pixels: original GPS/EXIF metadata is not copied into the diary.
actor MealPhotoProcessor {
  func jpeg(from data: Data) throws -> Data {
    guard data.count <= 25_000_000,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 1280,
        ] as CFDictionary)
    else { throw NutritionError.invalidPhoto }
    for quality in [0.8, 0.6, 0.4, 0.2] {
      let output = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
      else { throw NutritionError.invalidPhoto }
      CGImageDestinationAddImage(
        destination, image,
        [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
      if CGImageDestinationFinalize(destination), output.length <= 600_000 {
        return output as Data
      }
    }
    throw NutritionError.invalidPhoto
  }
}
