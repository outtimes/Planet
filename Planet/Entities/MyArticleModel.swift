import Foundation
import AVKit

class MyArticleModel: ArticleModel, Codable {
    @Published var link: String
    @Published var summary: String? = nil

    // populated when initializing
    unowned var planet: MyPlanetModel! = nil
    var draft: DraftModel? = nil

    lazy var path = planet.articlesPath.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    lazy var publicBasePath = planet.publicBasePath.appendingPathComponent(id.uuidString, isDirectory: true)
    lazy var publicIndexPath = publicBasePath.appendingPathComponent("index.html", isDirectory: false)
    lazy var publicInfoPath = publicBasePath.appendingPathComponent("article.json", isDirectory: false)

    var publicArticle: PublicArticleModel {
        PublicArticleModel(
            id: id,
            link: link,
            title: title,
            content: content,
            created: created,
            hasVideo: hasVideo,
            videoFilename: videoFilename,
            hasAudio: hasAudio,
            audioFilename: audioFilename,
            audioDuration: getAudioDuration(name: audioFilename),
            audioByteLength: getAttachmentByteLength(name: audioFilename),
            attachments: attachments,
            heroImage: socialImageURL?.absoluteString
        )
    }
    var browserURL: URL? {
        if let domain = planet.domain {
            if domain.hasSuffix(".eth") {
                return URL(string: "https://\(domain).limo/\(id.uuidString)/")
            }
            if domain.hasSuffix(".bit") {
                return URL(string: "https://\(domain).cc/\(id.uuidString)/")
            }
            if domain.hasCommonTLDSuffix() {
                return URL(string: "https://\(domain)/\(id.uuidString)/")
            }
        }
        return URL(string: "\(IPFSDaemon.preferredGateway())/ipns/\(planet.ipns)\(link)")
    }
    var socialImageURL: URL? {
        if let heroImage = getHeroImage(), let baseURL = browserURL {
            return baseURL.appendingPathComponent(heroImage)
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, link, title, content, summary, created, starred, videoFilename, audioFilename, attachments
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        link = try container.decode(String.self, forKey: .link)
        let title = try container.decode(String.self, forKey: .title)
        let content = try container.decode(String.self, forKey: .content)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        let created = try container.decode(Date.self, forKey: .created)
        let starred = try container.decodeIfPresent(Date.self, forKey: .starred)
        let videoFilename = try container.decodeIfPresent(String.self, forKey: .videoFilename)
        let audioFilename = try container.decodeIfPresent(String.self, forKey: .audioFilename)
        let attachments = try container.decodeIfPresent([String].self, forKey: .attachments)
        super.init(id: id,
                   title: title,
                   content: content,
                   created: created,
                   starred: starred,
                   videoFilename: videoFilename,
                   audioFilename: audioFilename,
                   attachments: attachments)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(link, forKey: .link)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(summary, forKey: .summary)
        try container.encode(created, forKey: .created)
        try container.encodeIfPresent(starred, forKey: .starred)
        try container.encodeIfPresent(videoFilename, forKey: .videoFilename)
        try container.encodeIfPresent(audioFilename, forKey: .audioFilename)
        try container.encodeIfPresent(attachments, forKey: .attachments)
    }

    init(id: UUID, link: String, title: String, content: String, summary: String?, created: Date, starred: Date?, videoFilename: String?, audioFilename: String?, attachments: [String]?) {
        self.link = link
        self.summary = summary
        super.init(id: id, title: title, content: content, created: created, starred: starred, videoFilename: videoFilename, audioFilename: audioFilename, attachments: attachments)
    }

    static func load(from filePath: URL, planet: MyPlanetModel) throws -> MyArticleModel {
        let filename = (filePath.lastPathComponent as NSString).deletingPathExtension
        guard let id = UUID(uuidString: filename) else {
            throw PlanetError.PersistenceError
        }
        let articleData = try Data(contentsOf: filePath)
        let article = try JSONDecoder.shared.decode(MyArticleModel.self, from: articleData)
        guard article.id == id else {
            throw PlanetError.PersistenceError
        }
        article.planet = planet
        let draftPath = planet.articleDraftsPath.appendingPathComponent(id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: draftPath.path) {
            article.draft = try? DraftModel.load(from: draftPath, article: article)
        }
        return article
    }

    static func compose(link: String?, date: Date = Date(), title: String, content: String, summary: String?, planet: MyPlanetModel) throws -> MyArticleModel {
        let id = UUID()
        let article = MyArticleModel(
            id: id,
            link: link ?? "/\(id.uuidString)/",
            title: title,
            content: content,
            summary: summary,
            created: date,
            starred: nil,
            videoFilename: nil,
            audioFilename: nil,
            attachments: nil
        )
        article.planet = planet
        try FileManager.default.createDirectory(at: article.publicBasePath, withIntermediateDirectories: true)
        return article
    }

    func getAttachmentURL(name: String) -> URL? {
        let path = publicBasePath.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        return nil
    }

    func getAttachmentByteLength(name: String?) -> Int? {
        guard let name = name, let url = getAttachmentURL(name: name) else {
            return nil
        }
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            return attr[.size] as? Int
        } catch {
            return nil
        }
    }

    func getAudioDuration(name: String?) -> Int? {
        guard let name = name, let url = getAttachmentURL(name: name) else {
            return nil
        }
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        return Int(CMTimeGetSeconds(duration))
    }

    func getHeroImage() -> String? {
        if self.hasVideoContent() {
            return "_videoThumbnail.png"
        }
        debugPrint("HeroImage: finding from \(attachments)")
        let images: [String]? = attachments?.compactMap {
            if $0.hasSuffix(".avif") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".jpg") || $0.hasSuffix(".png") || $0.hasSuffix(".webp") || $0.hasSuffix(".gif") || $0.hasSuffix(".tiff") {
                return $0
            } else {
                return nil
            }
        }
        debugPrint("HeroImage candidates: \(images?.count) \(images)")
        var firstImage: String? = nil
        if let items = images {
            for item in items {
                let imagePath = publicBasePath.appendingPathComponent(item, isDirectory: false)
                if let url = URL(string: imagePath.absoluteString) {
                    debugPrint("HeroImage: checking size of \(url.absoluteString)")
                    if let image = NSImage(contentsOf: url) {
                        if firstImage == nil {
                            firstImage = item
                        }
                        debugPrint("HeroImage: created NSImage from \(url.absoluteString)")
                        debugPrint("HeroImage: candidate size: \(image.size)")
                        if image.size.width >= 600 && image.size.height >= 400 {
                            debugPrint("HeroImage: \(item)")
                            return item
                        }
                    }
                } else {
                    debugPrint("HeroImage: invalid URL for item: \(item) \(imagePath)")
                }
            }
        }
        if firstImage != nil {
            debugPrint("HeroImage: return the first image anyway: \(firstImage)")
            return firstImage
        }
        debugPrint("HeroImage: NOT FOUND")
        return nil
    }

    func savePublic() throws {
        guard let template = planet.template else {
            throw PlanetError.MissingTemplateError
        }
        let articleHTML = try template.render(article: self)
        try articleHTML.data(using: .utf8)?.write(to: publicIndexPath)
        if self.hasVideoContent() {
            self.saveVideoThumbnail()
        }
        if self.hasHeroImage() || self.hasVideoContent() {
            self.saveHeroGrid()
        }
        try JSONEncoder.shared.encode(publicArticle).write(to: publicInfoPath)
    }

    func save() throws {
        try JSONEncoder.shared.encode(self).write(to: path)
    }

    func delete() {
        planet.articles.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: path)
        try? FileManager.default.removeItem(at: publicBasePath)
    }

    func hasHeroImage() -> Bool {
        return self.getHeroImage() != nil
    }

    func hasVideoContent() -> Bool {
        return videoFilename != nil
    }

    func hasAudioContent() -> Bool {
        return audioFilename != nil
    }

    func saveVideoThumbnail() {
        let videoThumbnailFilename = "_videoThumbnail.png"
        let videoThumbnailPath = publicBasePath.appendingPathComponent(videoThumbnailFilename)
        Task {
            if let thumbnail = await self.getVideoThumbnail(),
               let data = thumbnail.PNGData {
                try? data.write(to: videoThumbnailPath)
            }
        }
    }

    func saveHeroGrid() {
        guard let heroImageFilename = self.getHeroImage() else { return }
        let heroImagePath = publicBasePath.appendingPathComponent(heroImageFilename, isDirectory: false)
        guard let heroImage = NSImage(contentsOf: heroImagePath) else { return }
        let heroGridPNGFilename = "_grid.png"
        let heroGridPNGPath = publicBasePath.appendingPathComponent(heroGridPNGFilename)
        let heroGridJPEGFilename = "_grid.jpg"
        let heroGridJPEGPath = publicBasePath.appendingPathComponent(heroGridJPEGFilename)
        Task {
            if let grid = heroImage.resizeSquare(maxLength: 512) {
                if let gridPNGData = grid.PNGData {
                    try? gridPNGData.write(to: heroGridPNGPath)
                }
                if let gridJPEGData = grid.JPEGData {
                    try? gridJPEGData.write(to: heroGridJPEGPath)
                }
            }
        }
    }

    func getVideoThumbnail() async -> NSImage? {
        if self.hasVideoContent() {
            guard let videoFilename = self.videoFilename else {
                return nil
            }
            do {
                let url = self.publicBasePath.appendingPathComponent(videoFilename)
                let asset = AVURLAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                let cgImage = try imageGenerator.copyCGImage(at: .zero,
                                                            actualTime: nil)
                return NSImage(cgImage: cgImage, size: .zero)
            } catch {
                print(error.localizedDescription)

                return nil
            }
        }
        return nil
    }
}

extension MyArticleModel {
    static var placeholder: MyArticleModel {
        MyArticleModel(
            id: UUID(),
            link: "/example/",
            title: "Example Article",
            content: "This is an example article.",
            summary: "This is an example article.",
            created: Date(),
            starred: nil,
            videoFilename: nil,
            audioFilename: nil,
            attachments: nil
        )
    }
}

struct BackupArticleModel: Codable {
    let id: UUID
    let link: String
    let title: String
    let content: String
    let summary: String?
    let created: Date
    let videoFilename: String?
    let audioFilename: String?
    let attachments: [String]?
}
