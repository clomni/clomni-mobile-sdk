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
/// memory and on disk; `fallback` until it is here, and instead of it when it cannot come (`primary_soft`, or the
/// `placeholder` colour, unless a view is given). Never both: a logo with transparent parts shows what is behind it,
/// not a grey disc and an initial (CM-087). A kept picture is there in the first frame, offline too; only one that
/// came over the network fades in (DESIGN-PASS-3 C2).
struct RemoteImage<Fallback: View>: View {
    let url: URL
    let kind: ImageSizing.Kind
    let points: Double
    let theme: ClomniTheme
    var fit = false
    let fallback: Fallback
    @Environment(\.displayScale) private var scale
    @Environment(\.clomniLoadsRemoteImages) private var loadsImages
    @StateObject private var loader = ImageLoader()

    private var sized: URL {
        ImageSizing.url(url, kind: kind, points: points, scale: Double(scale))
    }

    var body: some View {
        let shown = loader.image ?? (loadsImages ? ImageCache.shared.kept(sized) : nil)
        ZStack {
            if let image = shown {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
            } else {
                fallback
            }
        }
        .animation(loader.fromNetwork ? .easeOut(duration: 0.2) : nil, value: shown != nil)
        .task(id: sized) {
            guard loadsImages else { return }
            await loader.load(sized)
        }
    }
}

extension RemoteImage where Fallback == Color {
    init(url: URL, kind: ImageSizing.Kind, points: Double, theme: ClomniTheme, fit: Bool = false,
         placeholder: Color? = nil) {
        self.init(url: url, kind: kind, points: points, theme: theme, fit: fit,
                  fallback: placeholder ?? theme.colors.primarySoft.color)
    }
}

@MainActor
final class ImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    /// It did not load (no network, not found): the caller may show something else.
    @Published private(set) var failed = false
    /// It came over the network just now, so it fades in; a kept one is simply there.
    private(set) var fromNetwork = false

    func load(_ url: URL) async {
        if let kept = ImageCache.shared.kept(url) {
            image = kept
            failed = false
            return
        }
        let loaded = await ImageCache.shared.image(url)
        fromNetwork = loaded != nil
        image = loaded
        failed = loaded == nil
    }
}

/// Decoded pictures in memory, their files in a disk cache of their own (not the app's URLCache). A panel picture's
/// URL changes with its version, so a kept copy is the picture: it is shown without asking the server, offline too,
/// whatever the response's cache headers said.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let disk: URLCache
    private let session: URLSession

    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ClomniImages", isDirectory: true)
        disk = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024, directory: directory)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = disk
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory.countLimit = 100
    }

    /// Keeps a picture for its URL (the tests' pictures, with no network).
    func keep(_ image: UIImage, for url: URL) {
        memory.setObject(image, forKey: url as NSURL)
    }

    /// The picture if it is kept, in memory or on disk; nothing is asked of the network.
    func kept(_ url: URL) -> UIImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        guard let data = disk.cachedResponse(for: URLRequest(url: url))?.data, let image = UIImage(data: data) else {
            return nil
        }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    func image(_ url: URL) async -> UIImage? {
        if let image = kept(url) { return image }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let image = UIImage(data: data) else { return nil }
        disk.storeCachedResponse(CachedURLResponse(response: response, data: data, storagePolicy: .allowed),
                                 for: URLRequest(url: url))
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}
#endif
