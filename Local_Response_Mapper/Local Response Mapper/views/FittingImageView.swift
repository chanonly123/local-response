import SwiftUI

struct FittingImageView: View {
    private let image: Image
    private let originalSize: CGSize  // Provide the actual size of the image

    init(image: Image, originalSize: CGSize) {
        self.image = image
        self.originalSize = originalSize
    }

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let shouldScaleDown = originalSize.width > containerSize.width || originalSize.height > containerSize.height

            image
                .resizable()
                .if(shouldScaleDown) {
                    $0.scaledToFit()
                }
                .frame(
                    width: shouldScaleDown ? nil : originalSize.width,
                    height: shouldScaleDown ? nil : originalSize.height
                )
                .position(x: containerSize.width / 2, y: containerSize.height / 2)
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool,
                             transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
