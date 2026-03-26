import Foundation

// MARK: - Log Entry

struct LogEntry {
    let timestamp: Date
    let action: String      // "이동" / "건너뜀" / "오류"
    let fileName: String
    let sourcePath: String
    let destPath: String
    let errorMessage: String
    let targetFolders: String
    let outputFolders: String
}

// MARK: - XLSX Exporter

struct XLSXExporter {

    static let headers = ["시간", "작업", "파일명", "원본 경로", "이동 경로", "오류", "대상 폴더", "출력 폴더"]

    static func export(entries: [LogEntry], to url: URL) throws {
        let rows: [[String]] = [headers] + entries.map {
            [
                DateFormatter.logTimestamp.string(from: $0.timestamp),
                $0.action,
                $0.fileName,
                $0.sourcePath,
                $0.destPath,
                $0.errorMessage,
                $0.targetFolders,
                $0.outputFolders,
            ]
        }
        let data = buildXLSX(rows: rows)
        try data.write(to: url)
    }

    // MARK: - XLSX build

    private static func buildXLSX(rows: [[String]]) -> Data {
        // Collect shared strings
        var strings: [String] = []
        var stringIndex: [String: Int] = [:]

        func si(_ s: String) -> Int {
            if let i = stringIndex[s] { return i }
            let i = strings.count
            strings.append(s)
            stringIndex[s] = i
            return i
        }
        for row in rows { for cell in row { _ = si(cell) } }

        // sheet1.xml
        var sheet = xmlDecl
        sheet += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#
        for (r, row) in rows.enumerated() {
            sheet += #"<row r="\#(r + 1)">"#
            for (c, cell) in row.enumerated() {
                let ref = colLetter(c) + "\(r + 1)"
                let style = r == 0 ? #" s="1""# : ""
                sheet += #"<c r="\#(ref)" t="s"\#(style)><v>\#(si(cell))</v></c>"#
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"

        // sharedStrings.xml
        var ss = xmlDecl
        ss += #"<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\#(strings.count)" uniqueCount="\#(strings.count)">"#
        for s in strings { ss += #"<si><t xml:space="preserve">\#(xmlEsc(s))</t></si>"# }
        ss += "</sst>"

        let files: [(String, String)] = [
            ("[Content_Types].xml",        contentTypes),
            ("_rels/.rels",                rels),
            ("xl/workbook.xml",            workbook),
            ("xl/_rels/workbook.xml.rels", workbookRels),
            ("xl/worksheets/sheet1.xml",   sheet),
            ("xl/styles.xml",              styles),
            ("xl/sharedStrings.xml",       ss),
        ]
        return buildZip(files.map { ($0, $1.data(using: .utf8)!) })
    }

    // MARK: - Static XML content

    private static let xmlDecl = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    private static let contentTypes = #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
"""#

    private static let rels = #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"""#

    private static let workbook = #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="정리 로그" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"""#

    private static let workbookRels = #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"""#

    /// Style 0 = normal, Style 1 = bold (header row)
    private static let styles = #"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><name val="Calibri"/></font>
</fonts>
<fills count="2">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
</fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="2">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>
</cellXfs>
</styleSheet>
"""#

    // MARK: - ZIP (STORE, no compression)

    private static func buildZip(files: [(String, Data)]) -> Data {
        var zip   = Data()
        var cdir  = Data()
        var offsets: [UInt32] = []

        let (dosTime, dosDate) = dosDateTime()

        for (name, data) in files {
            offsets.append(UInt32(zip.count))
            let nameBytes = Data(name.utf8)
            let crc       = crc32(data)
            let size      = UInt32(data.count)

            zip.le32(0x04034b50); zip.le16(20); zip.le16(0); zip.le16(0)
            zip.le16(dosTime);    zip.le16(dosDate)
            zip.le32(crc);        zip.le32(size); zip.le32(size)
            zip.le16(UInt16(nameBytes.count)); zip.le16(0)
            zip.append(nameBytes); zip.append(data)
        }

        let cdirOffset = UInt32(zip.count)
        for (i, (name, data)) in files.enumerated() {
            let nameBytes = Data(name.utf8)
            let crc       = crc32(data)
            let size      = UInt32(data.count)

            cdir.le32(0x02014b50); cdir.le16(20); cdir.le16(20); cdir.le16(0); cdir.le16(0)
            cdir.le16(dosTime);    cdir.le16(dosDate)
            cdir.le32(crc);        cdir.le32(size); cdir.le32(size)
            cdir.le16(UInt16(nameBytes.count)); cdir.le16(0); cdir.le16(0)
            cdir.le16(0); cdir.le16(0); cdir.le32(0)
            cdir.le32(offsets[i])
            cdir.append(nameBytes)
        }

        zip.append(cdir)
        zip.le32(0x06054b50); zip.le16(0); zip.le16(0)
        zip.le16(UInt16(files.count)); zip.le16(UInt16(files.count))
        zip.le32(UInt32(cdir.count)); zip.le32(cdirOffset); zip.le16(0)
        return zip
    }

    // MARK: - Helpers

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    private static func dosDateTime() -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let t = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let d = UInt16((((c.year ?? 1980) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        return (t, d)
    }

    private static func colLetter(_ index: Int) -> String {
        var result = ""; var n = index
        repeat {
            result = String(UnicodeScalar(65 + n % 26)!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private static func xmlEsc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { var x = v.littleEndian; append(contentsOf: withUnsafeBytes(of: &x, Array.init)) }
    mutating func le32(_ v: UInt32) { var x = v.littleEndian; append(contentsOf: withUnsafeBytes(of: &x, Array.init)) }
}
