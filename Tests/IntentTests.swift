import Foundation
import AppIntents

@main struct IntentTests {
    static func main() async throws {
        let input = IntentFile(data:Data("automacao".utf8),filename:"teste.txt")
        let compress = CompressTabajaraIntent(); compress.files = [input]
        let result = try await compress.perform()
        guard let zip = result.value else { throw ArchiveError("Intent did not return archive") }
        let extract = ExtractTabajaraIntent(); extract.archive = zip
        let extracted = try await extract.perform()
        guard let files = extracted.value, files.count == 1, String(data:files[0].data,encoding:.utf8) == "automacao" else { throw ArchiveError("Intent roundtrip failed") }
        if let url = zip.fileURL { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }
        if let url = extracted.value?.first?.fileURL { try? FileManager.default.removeItem(at:url.deletingLastPathComponent().deletingLastPathComponent()) }
        print("PASS: native App Intents compression/extraction roundtrip")
    }
}
