#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// A picture of the panel's (logo, avatars, header picture) at the width this screen needs and as WebP, cached in
/// memory and on disk; `primary_soft` until it is here (or `placeholder` when given).
struct RemoteImage: View {
    let url: URL
    let kind: ImageSizing.Kind
    let points: Double
    let theme: ClomniTheme
    var fit = false
    var placeholder: Color?
    @Environment(\.displayScale) private var scale
    @Environment(\.clomniLoadsRemoteImages) private var loadsImages
    @StateObject private var loader = ImageLoader()

    private var sized: URL {
        ImageSizing.url(url, kind: kind, points: points, scale: Double(scale))
    }

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
            } else {
                placeholder ?? theme.colors.primarySoft.color
            }
        }
        .animation(.easeOut(duration: 0.2), value: loader.image != nil)
        .task(id: sized) {
            guard loadsImages else { return }
            await loader.load(sized)
        }
    }
}

@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    func load(_ url: URL) async {
        image = await ImageCache.shared.image(url)
    }
}

/// Decoded pictures in memory, their files in a disk cache of their own (not the app's URLCache).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ClomniImages", isDirectory: true)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024,
                                          directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory.countLimit = 100
    }

    func image(_ url: URL) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}
#endif
