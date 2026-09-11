import Foundation

/// 테스트 전용 최소 PNG 디코더 (SOO-1325).
///
/// 왜 직접 만드나 — 메뉴 막대 아이콘의 template 불변식("알파가 전부 불투명하면 안 된다")은
/// **픽셀을 봐야만** 검증된다. 그런데 헤더만 읽는 기존 테스트와 달리 픽셀에 닿으려면 IDAT 의
/// DEFLATE 를 풀어야 하고, Linux 의 swift-corelibs-Foundation 에는 zlib 을 노출하는 공개
/// API 가 없다(`Compression` 은 Apple 전용). 선택지는 셋이었다:
///
///   1. `Package.swift` 에 zlib systemLibrary 타깃 추가 — Mac 빌드 환경에 헤더 의존을 새로 건다.
///   2. 테스트에서 `python3` 을 `Process` 로 호출 — python3 이 없으면 검사가 조용히 건너뛰어진다.
///   3. (채택) 테스트 타깃 안에 inflate 를 직접 구현 — 새 의존성 0, 어느 환경에서도 같게 돈다.
///
/// icns 컨테이너와 PNG IHDR 을 이미 손으로 파싱하고 있는 이 테스트 타깃의 기조와도 맞다.
///
/// 범위는 `Scripts/make-icons.py`(Pillow)가 실제로 내보내는 형태로 좁혔다 — 8bit 심도,
/// 논인터레이스. 그 밖은 에러를 던져 조용한 통과를 막는다.
enum PNGDecodeError: Error, CustomStringConvertible {
    case notPNG
    case truncated
    case unsupported(String)
    case corruptStream(String)

    var description: String {
        switch self {
        case .notPNG: return "PNG 시그니처가 아닙니다"
        case .truncated: return "파일이 잘렸습니다"
        case .unsupported(let why): return "지원하지 않는 PNG 입니다: \(why)"
        case .corruptStream(let why): return "압축 스트림이 손상됐습니다: \(why)"
        }
    }
}

/// 디코드된 8bit PNG. `samples` 는 행 우선, 픽셀당 `samplesPerPixel` 개가 연속으로 들어간다.
struct DecodedPNG {
    let width: Int
    let height: Int
    /// PNG color type — 0 gray, 2 RGB, 4 gray+alpha, 6 RGBA.
    let colorType: UInt8
    let samplesPerPixel: Int
    let samples: [UInt8]

    var hasAlpha: Bool { colorType == 4 || colorType == 6 }

    /// 픽셀의 알파. 알파 채널이 없으면 255 로 본다.
    func alpha(x: Int, y: Int) -> UInt8 {
        guard hasAlpha else { return 255 }
        return samples[(y * width + x) * samplesPerPixel + (samplesPerPixel - 1)]
    }

    /// 픽셀의 색 채널들(알파 제외).
    func colorChannels(x: Int, y: Int) -> ArraySlice<UInt8> {
        let base = (y * width + x) * samplesPerPixel
        let colorCount = hasAlpha ? samplesPerPixel - 1 : samplesPerPixel
        return samples[base..<(base + colorCount)]
    }
}

enum PNGPixelReader {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func decode(_ data: Data) throws -> DecodedPNG {
        let bytes = [UInt8](data)
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { throw PNGDecodeError.notPNG }

        var width = 0
        var height = 0
        var bitDepth: UInt8 = 0
        var colorType: UInt8 = 0
        var idat: [UInt8] = []
        var offset = 8

        while offset + 8 <= bytes.count {
            let length = Int(readUInt32BE(bytes, offset))
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let bodyStart = offset + 8
            guard bodyStart + length + 4 <= bytes.count else { throw PNGDecodeError.truncated }

            switch type {
            case "IHDR":
                guard length >= 13 else { throw PNGDecodeError.truncated }
                width = Int(readUInt32BE(bytes, bodyStart))
                height = Int(readUInt32BE(bytes, bodyStart + 4))
                bitDepth = bytes[bodyStart + 8]
                colorType = bytes[bodyStart + 9]
                guard bytes[bodyStart + 12] == 0 else {
                    throw PNGDecodeError.unsupported("인터레이스")
                }
            case "IDAT":
                idat.append(contentsOf: bytes[bodyStart..<(bodyStart + length)])
            case "IEND":
                offset = bytes.count
                continue
            default:
                break
            }

            offset = bodyStart + length + 4 // 청크 본문 + CRC
        }

        guard bitDepth == 8 else { throw PNGDecodeError.unsupported("bit depth \(bitDepth)") }
        guard width > 0, height > 0, !idat.isEmpty else { throw PNGDecodeError.truncated }

        let samplesPerPixel: Int
        switch colorType {
        case 0: samplesPerPixel = 1
        case 2: samplesPerPixel = 3
        case 4: samplesPerPixel = 2
        case 6: samplesPerPixel = 4
        default: throw PNGDecodeError.unsupported("color type \(colorType)")
        }

        // zlib 래퍼: CMF/FLG 2바이트를 건너뛰고 raw DEFLATE 를 푼다(끝의 Adler-32 는 검사하지 않는다).
        guard idat.count > 2 else { throw PNGDecodeError.truncated }
        let raw = try inflate(Array(idat[2...]))

        return DecodedPNG(
            width: width,
            height: height,
            colorType: colorType,
            samplesPerPixel: samplesPerPixel,
            samples: try unfilter(raw, width: width, height: height, samplesPerPixel: samplesPerPixel)
        )
    }

    private static func readUInt32BE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    // MARK: - PNG 행 필터 해제

    /// 각 행은 1바이트 필터 타입 뒤에 픽셀 바이트가 온다. 필터는 직전 픽셀(a)·윗행(b)·
    /// 윗행의 직전 픽셀(c) 을 참조하는 차분 예측이다 (PNG 규격 9.2).
    private static func unfilter(
        _ raw: [UInt8], width: Int, height: Int, samplesPerPixel: Int
    ) throws -> [UInt8] {
        let stride = width * samplesPerPixel
        guard raw.count >= height * (stride + 1) else {
            throw PNGDecodeError.corruptStream("행 데이터가 모자랍니다 (\(raw.count) bytes)")
        }

        var out = [UInt8](repeating: 0, count: height * stride)

        for y in 0..<height {
            let filter = raw[y * (stride + 1)]
            let src = y * (stride + 1) + 1
            let dst = y * stride
            let up = dst - stride

            for i in 0..<stride {
                let a = i >= samplesPerPixel ? Int(out[dst + i - samplesPerPixel]) : 0
                let b = y > 0 ? Int(out[up + i]) : 0
                let c = (y > 0 && i >= samplesPerPixel) ? Int(out[up + i - samplesPerPixel]) : 0
                let x = Int(raw[src + i])

                let value: Int
                switch filter {
                case 0: value = x
                case 1: value = x + a
                case 2: value = x + b
                case 3: value = x + (a + b) / 2
                case 4: value = x + paeth(a, b, c)
                default: throw PNGDecodeError.corruptStream("행 \(y) 의 필터 타입 \(filter)")
                }
                out[dst + i] = UInt8(value & 0xFF)
            }
        }

        return out
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        return pb <= pc ? b : c
    }

    // MARK: - DEFLATE (RFC 1951)

    /// 비트를 LSB 우선으로 읽는다 — DEFLATE 의 규약.
    private struct BitReader {
        let bytes: [UInt8]
        var position = 0
        var buffer: UInt32 = 0
        var count = 0

        mutating func read(_ needed: Int) throws -> Int {
            while count < needed {
                guard position < bytes.count else { throw PNGDecodeError.corruptStream("비트가 모자랍니다") }
                buffer |= UInt32(bytes[position]) << UInt32(count)
                position += 1
                count += 8
            }
            let value = Int(buffer & ((1 << UInt32(needed)) - 1))
            buffer >>= UInt32(needed)
            count -= needed
            return value
        }

        mutating func alignToByte() {
            buffer = 0
            count = 0
        }
    }

    /// 정규 허프만 코드 — 길이별 개수(`count`)와 그 순서대로 늘어놓은 심볼(`symbol`)로만 표현한다.
    /// 트리를 만들지 않고 길이를 1부터 늘려가며 구간을 좁히는 방식(zlib `puff.c` 와 동형)이라
    /// 테이블이 작고 구현이 짧다.
    private struct Huffman {
        var count: [Int]
        var symbol: [Int]

        init(lengths: [Int], maxBits: Int) {
            count = [Int](repeating: 0, count: maxBits + 1)
            for length in lengths where length > 0 { count[length] += 1 }

            // 길이가 짧은 코드부터 차례로 놓이도록 길이별 시작 위치를 먼저 잡는다.
            var cursor = [Int](repeating: 0, count: maxBits + 1)
            var total = 0
            for length in 1...maxBits {
                cursor[length] = total
                total += count[length]
            }

            symbol = [Int](repeating: 0, count: total)
            for (value, length) in lengths.enumerated() where length > 0 {
                symbol[cursor[length]] = value
                cursor[length] += 1
            }
        }
    }

    private static func decodeSymbol(_ huffman: Huffman, _ reader: inout BitReader) throws -> Int {
        var code = 0
        var first = 0
        var index = 0

        for length in 1..<huffman.count.count {
            code |= try reader.read(1)
            let available = huffman.count[length]
            if code - first < available { return huffman.symbol[index + (code - first)] }
            index += available
            first = (first + available) << 1
            code <<= 1
        }

        throw PNGDecodeError.corruptStream("허프만 코드를 해석하지 못했습니다")
    }

    private static let lengthBase = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
    ]
    private static let lengthExtra = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]
    private static let distanceBase = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ]
    private static let distanceExtra = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
    ]
    /// 코드 길이 알파벳의 전송 순서 (RFC 1951 §3.2.7).
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static func inflate(_ input: [UInt8]) throws -> [UInt8] {
        var reader = BitReader(bytes: input)
        var out: [UInt8] = []
        out.reserveCapacity(input.count * 4)

        while true {
            let isFinal = try reader.read(1)
            let type = try reader.read(2)

            switch type {
            case 0:
                reader.alignToByte()
                guard reader.position + 4 <= input.count else { throw PNGDecodeError.corruptStream("stored 블록 헤더") }
                let length = Int(input[reader.position]) | (Int(input[reader.position + 1]) << 8)
                reader.position += 4 // LEN + NLEN
                guard reader.position + length <= input.count else { throw PNGDecodeError.corruptStream("stored 블록 본문") }
                out.append(contentsOf: input[reader.position..<(reader.position + length)])
                reader.position += length
            case 1:
                try inflateBlock(&reader, &out, literals: fixedLiteralHuffman, distances: fixedDistanceHuffman)
            case 2:
                let (literals, distances) = try readDynamicTables(&reader)
                try inflateBlock(&reader, &out, literals: literals, distances: distances)
            default:
                throw PNGDecodeError.corruptStream("예약된 블록 타입 3")
            }

            if isFinal == 1 { return out }
        }
    }

    private static let fixedLiteralHuffman: Huffman = {
        var lengths = [Int](repeating: 8, count: 288)
        for symbol in 144..<256 { lengths[symbol] = 9 }
        for symbol in 256..<280 { lengths[symbol] = 7 }
        return Huffman(lengths: lengths, maxBits: 15)
    }()

    private static let fixedDistanceHuffman = Huffman(lengths: [Int](repeating: 5, count: 30), maxBits: 15)

    private static func readDynamicTables(_ reader: inout BitReader) throws -> (Huffman, Huffman) {
        let literalCount = try reader.read(5) + 257
        let distanceCount = try reader.read(5) + 1
        let codeLengthCount = try reader.read(4) + 4

        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount { codeLengths[codeLengthOrder[index]] = try reader.read(3) }
        let codeLengthHuffman = Huffman(lengths: codeLengths, maxBits: 7)

        var lengths: [Int] = []
        lengths.reserveCapacity(literalCount + distanceCount)

        while lengths.count < literalCount + distanceCount {
            let symbol = try decodeSymbol(codeLengthHuffman, &reader)
            switch symbol {
            case 0..<16:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else { throw PNGDecodeError.corruptStream("반복할 직전 길이가 없습니다") }
                let repeats = try reader.read(2) + 3
                lengths.append(contentsOf: [Int](repeating: previous, count: repeats))
            case 17:
                lengths.append(contentsOf: [Int](repeating: 0, count: try reader.read(3) + 3))
            case 18:
                lengths.append(contentsOf: [Int](repeating: 0, count: try reader.read(7) + 11))
            default:
                throw PNGDecodeError.corruptStream("코드 길이 심볼 \(symbol)")
            }
        }

        guard lengths.count == literalCount + distanceCount else {
            throw PNGDecodeError.corruptStream("코드 길이 개수가 선언과 다릅니다")
        }

        return (
            Huffman(lengths: Array(lengths[0..<literalCount]), maxBits: 15),
            Huffman(lengths: Array(lengths[literalCount...]), maxBits: 15)
        )
    }

    private static func inflateBlock(
        _ reader: inout BitReader, _ out: inout [UInt8], literals: Huffman, distances: Huffman
    ) throws {
        while true {
            let symbol = try decodeSymbol(literals, &reader)

            if symbol < 256 {
                out.append(UInt8(symbol))
                continue
            }
            if symbol == 256 { return }

            let lengthIndex = symbol - 257
            guard lengthIndex < lengthBase.count else { throw PNGDecodeError.corruptStream("길이 심볼 \(symbol)") }
            let length = lengthBase[lengthIndex] + (try reader.read(lengthExtra[lengthIndex]))

            let distanceSymbol = try decodeSymbol(distances, &reader)
            guard distanceSymbol < distanceBase.count else {
                throw PNGDecodeError.corruptStream("거리 심볼 \(distanceSymbol)")
            }
            let distance = distanceBase[distanceSymbol] + (try reader.read(distanceExtra[distanceSymbol]))
            guard distance <= out.count else { throw PNGDecodeError.corruptStream("거리가 출력 범위를 넘습니다") }

            // 겹치는 복사가 정상 동작이므로(LZ77) 한 바이트씩 붙인다.
            let start = out.count - distance
            for index in 0..<length { out.append(out[start + index]) }
        }
    }
}
