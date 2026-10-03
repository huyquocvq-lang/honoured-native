import CoreImage
import UIKit

/// Turns a stored contract signature into what the Icon card draws: the ink as
/// white strokes on transparency, at most `maxWidth` pixels wide and within the
/// cache's size limit. The web app saves light ink on a painted black
/// background and crops it to the ink; an image with a light background is
/// inverted first so its dark ink becomes the mask.
enum IconSignatureImage {
    static let maxWidth: CGFloat = 480

    static func prepare(_ data: Data, maxBytes: Int = IconSignatureCache.maxBytes) -> Data? {
        guard let source = CIImage(data: data), source.extent.width >= 1, source.extent.height >= 1 else { return nil }
        let context = CIContext()
        let ink = averageLuminance(of: source, in: context) < 0.5 ? source : source.applyingFilter("CIColorInvert")
        let mask = ink.applyingFilter("CIMaskToAlpha")

        var width = min(maxWidth, source.extent.width)
        while width >= 60 {
            let scale = width / source.extent.width
            let scaled = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let extent = scaled.extent.integral
            guard let image = context.createCGImage(scaled, from: extent) else { return nil }
            if let png = UIImage(cgImage: image).pngData(), png.count <= maxBytes {
                return png
            }
            width *= 0.7
        }
        return nil
    }

    private static func averageLuminance(of image: CIImage, in context: CIContext) -> CGFloat {
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            average, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil
        )
        return (0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])) / 255
    }
}
