import Foundation

/// Loads and manages chunk data from the bundled chunks.json.
/// Mirrors Python's chunker.Chunk + vector_store chunk_id mapping.
class ChunkStore {
    private(set) var chunks: [String: ChunkData] = [:]
    private(set) var orderedChunkIds: [String] = []
    private(set) var imageBasePath: URL?

    var count: Int { orderedChunkIds.count }

    func load() throws {
        guard let chunksURL = Bundle.main.url(forResource: "chunks", withExtension: "json") else {
            throw ChunkStoreError.fileNotFound("chunks.json not found in bundle")
        }
        try load(from: chunksURL)

        if let imagesDir = Bundle.main.url(forResource: "images", withExtension: nil) {
            imageBasePath = imagesDir
        }
    }

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let chunkList = try decoder.decode([ChunkData].self, from: data)

        orderedChunkIds = chunkList.map { $0.chunkId }
        chunks = Dictionary(uniqueKeysWithValues: chunkList.map { ($0.chunkId, $0) })
    }

    func chunk(for id: String) -> ChunkData? {
        chunks[id]
    }

    /// Resolve an image path from chunk metadata to a local file URL.
    /// The export script strips directory prefixes, so images are just filenames.
    func resolveImageURL(_ imagePath: String) -> URL? {
        let filename = (imagePath as NSString).lastPathComponent
        // Try bundle Resources/images/ first
        if let base = imageBasePath {
            let url = base.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Fallback: try bundle root
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}

enum ChunkStoreError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let msg): return msg
        }
    }
}
