import UIKit
import XCTest

final class IconSignatureImageTests: XCTestCase {
    /// What the web app stores: light ink on a painted background, cropped to
    /// the ink. Opaque, like the canvas export.
    private func signaturePNG(width: CGFloat, height: CGFloat, background: UIColor, ink: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: width * 0.05, y: height * 0.8))
            path.addCurve(to: CGPoint(x: width * 0.95, y: height * 0.4),
                          controlPoint1: CGPoint(x: width * 0.3, y: 0), controlPoint2: CGPoint(x: width * 0.6, y: height))
            ink.setStroke()
            path.lineWidth = max(3, height * 0.05)
            path.stroke()
        }
        return image.pngData()!
    }

    private func alpha(of png: Data, atFraction point: CGPoint) throws -> UInt8 {
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let x = CGFloat(image.width) * point.x
        let y = CGFloat(image.height) * point.y
        context.draw(image, in: CGRect(x: -x, y: -(CGFloat(image.height) - y - 1), width: CGFloat(image.width), height: CGFloat(image.height)))
        return pixel[3]
    }

    /// The strongest ink in the image.
    private func maxAlpha(of png: Data) throws -> UInt8 {
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
    }

    func testLightInkOnBlackBecomesInkOnTransparency() throws {
        let stored = signaturePNG(width: 900, height: 300, background: .black, ink: UIColor(white: 0.96, alpha: 1))
        let prepared = try XCTUnwrap(IconSignatureImage.prepare(stored))
        let image = try XCTUnwrap(UIImage(data: prepared))
        XCTAssertLessThanOrEqual(image.size.width * image.scale, IconSignatureImage.maxWidth)
        XCTAssertLessThanOrEqual(prepared.count, IconSignatureCache.maxBytes)
        XCTAssertEqual(try alpha(of: prepared, atFraction: CGPoint(x: 0.02, y: 0.05)), 0, "the background is transparent")
        XCTAssertGreaterThan(try maxAlpha(of: prepared), 200, "the ink stays")
    }

    func testDarkInkOnALightBackgroundIsInvertedFirst() throws {
        let stored = signaturePNG(width: 400, height: 120, background: .white, ink: .black)
        let prepared = try XCTUnwrap(IconSignatureImage.prepare(stored))
        XCTAssertEqual(try alpha(of: prepared, atFraction: CGPoint(x: 0.02, y: 0.05)), 0)
        XCTAssertGreaterThan(try maxAlpha(of: prepared), 200)
    }

    func testSmallSignaturesAreNotScaledUp() throws {
        let stored = signaturePNG(width: 200, height: 60, background: .black, ink: .white)
        let image = try XCTUnwrap(IconSignatureImage.prepare(stored).flatMap(UIImage.init(data:)))
        XCTAssertEqual(image.size.width * image.scale, 200)
    }

    func testShrinksUntilItFitsTheByteLimit() throws {
        let stored = signaturePNG(width: 900, height: 300, background: .black, ink: .white)
        let tight = 6 * 1024
        let prepared = try XCTUnwrap(IconSignatureImage.prepare(stored, maxBytes: tight))
        XCTAssertLessThanOrEqual(prepared.count, tight)
    }

    func testRejectsDataThatIsNotAnImage() {
        XCTAssertNil(IconSignatureImage.prepare(Data("not a png".utf8)))
        XCTAssertNil(IconSignatureImage.prepare(Data()))
    }
}
