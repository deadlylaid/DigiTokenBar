import CoreGraphics

/// Fitting a sprite into the menu bar slot **without changing its aspect ratio**.
///
/// Sprite canvases are not all square, so stretching one to fill a square box distorts it, and the
/// distortion only shows on the non-square ones. Every caller goes through this one formula.
enum SpriteFit {
    /// The source fitted inside a `width`×`height` box (contentMode .fit: it touches the box on one
    /// axis). An empty source (a failed decode) falls back to a square on the shorter side.
    static func size(for pixelSize: CGSize, width: CGFloat, height: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            let side = min(width, height)
            return CGSize(width: side, height: side)
        }
        let scale = min(width / pixelSize.width, height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }
}
