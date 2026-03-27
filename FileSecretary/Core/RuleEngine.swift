import Foundation

// MARK: - FileTypeCategory

enum FileTypeCategory: String, Codable, CaseIterable {
    case image    = "이미지"
    case video    = "동영상"
    case document = "문서"
    case adobe    = "어도비"
    case font     = "폰트"
    case audio    = "오디오"
    case archive  = "압축파일"

    var extensions: [String] {
        switch self {
        case .image:    return ["jpg","jpeg","png","gif","bmp","tiff","heic","webp","svg"]
        case .video:    return ["mp4","mov","avi","mkv","wmv","m4v"]
        case .document: return ["pdf","doc","docx","ppt","pptx","xls","xlsx","csv","txt","md","hwp"]
        case .adobe:    return ["psd","psb","ai","eps","prproj","aep","aet","indd","indt","idml","xd","lrcat"]
        case .font:     return ["ttf","otf","woff","woff2","eot","fon","ttc"]
        case .audio:    return ["mp3","wav","aac","flac","ogg","m4a","wma","aiff","opus"]
        case .archive:  return ["zip","rar","7z","tar","gz","bz2","xz","dmg","iso"]
        }
    }

    static func from(fileExtension ext: String) -> FileTypeCategory? {
        let lower = ext.lowercased()
        return allCases.first { $0.extensions.contains(lower) }
    }
}

// MARK: - Category Model

struct Category: Codable, Identifiable, Equatable {
    var id: String
    var num: Int
    var name: String
    var conditionType: ConditionKind
    var types: [String]       // FileTypeCategory rawValues
    var keywords: [String]
    var logic: ConditionLogic?
    var outputIdx: Int        // 0 = 개별 모드, 1=A, 2=B, 3=C, 4=D

    enum ConditionKind: String, Codable {
        case keyword, type, both
    }

    enum ConditionLogic: String, Codable {
        case and, or
    }

    var folderName: String {
        String(format: "%02d_%@", num, name)
    }
}

// MARK: - ExcludeList / RulesData

struct ExcludeList: Codable {
    var keywords: [String]
    var extensions: [String]
}

struct RulesData: Codable {
    var version: Int
    var categories: [Category]
    var outputFolders: [String]
    var excludeList: ExcludeList
    var etcOutputIdx: Int

    init(version: Int, categories: [Category], outputFolders: [String], excludeList: ExcludeList, etcOutputIdx: Int = 0) {
        self.version = version
        self.categories = categories
        self.outputFolders = outputFolders
        self.excludeList = excludeList
        self.etcOutputIdx = etcOutputIdx
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version      = try c.decode(Int.self,        forKey: .version)
        categories   = try c.decode([Category].self, forKey: .categories)
        outputFolders = try c.decode([String].self,  forKey: .outputFolders)
        excludeList  = try c.decode(ExcludeList.self, forKey: .excludeList)
        etcOutputIdx = (try? c.decode(Int.self,      forKey: .etcOutputIdx)) ?? 0
    }
}

// MARK: - RuleEngine

class RuleEngine {

    /// Returns all categories that match the given file.
    func evaluate(file: URL, categories: [Category]) -> [Category] {
        categories.filter { matches(file: file, category: $0) }
    }

    func isExcluded(file: URL, excludeList: ExcludeList) -> Bool {
        let name = file.lastPathComponent.lowercased()
        let ext  = ".\(file.pathExtension.lowercased())"

        for kw in excludeList.keywords where name.contains(kw.lowercased()) { return true }
        for ex in excludeList.extensions where ext == ex.lowercased() || name == ex.lowercased() { return true }
        return false
    }

    // MARK: Private helpers

    private func matches(file: URL, category: Category) -> Bool {
        let name = file.deletingPathExtension().lastPathComponent.lowercased()
        let ext  = file.pathExtension.lowercased()

        switch category.conditionType {
        case .keyword:
            return matchesKeywords(name: name, keywords: category.keywords)
        case .type:
            return matchesTypes(ext: ext, types: category.types)
        case .both:
            let k = matchesKeywords(name: name, keywords: category.keywords)
            let t = matchesTypes(ext: ext, types: category.types)
            switch category.logic ?? .and {
            case .and: return k && t
            case .or:  return k || t
            }
        }
    }

    private func matchesKeywords(name: String, keywords: [String]) -> Bool {
        guard !keywords.isEmpty else { return false }
        return keywords.contains { name.contains($0.lowercased()) }
    }

    private func matchesTypes(ext: String, types: [String]) -> Bool {
        guard !types.isEmpty else { return false }
        return types.contains { FileTypeCategory(rawValue: $0)?.extensions.contains(ext) ?? false }
    }
}
