import XCTest

/// 아이콘 리소스 파일 자체의 무결성 회귀 테스트 (SOO-1319 / SOO-1320).
///
/// 왜 코어 테스트 타깃에 두는가 — 아이콘을 실제로 쓰는 `AppDelegate.swift` 는 `#if os(macOS)`
/// 안에 있어 Linux `swift build` 가 **단 한 줄도 검사하지 않는다.** 따라서 CI/에이전트 환경의
/// "빌드 통과" 는 아이콘이 온전하다는 증거가 되지 못한다. 대신 파일 포맷을 직접 파싱해
/// "잘린 icns", "빈 PNG", "크기가 어긋난 메뉴 막대 이미지" 같은 회귀를 Mac 없이 잡는다.
///
/// 리소스 경로는 `#filePath` 기준 상대 경로로 푼다. SwiftPM 리소스 번들(`.copy`)을 새로
/// 도입하지 않는 이유: 실행 타깃 리소스는 `HanyoungBadge_HanyoungBadgeApp.bundle` 로 감싸여
/// `.app` 복사 경로가 복잡해진다. `Scripts/build-app.sh` 가 직접 복사하는 단순 경로를 지킨다.
final class IconResourceTests: XCTestCase {
    /// `macos/Resources` — 이 파일(`macos/Tests/HanyoungBadgeCoreTests/...`) 기준 상대 경로.
    private static let resourcesDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // HanyoungBadgeCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // macos
        .appendingPathComponent("Resources")

    /// `Scripts/make-icons.py` 가 넣는 icns 타입과 각 엔트리의 픽셀 크기.
    /// 하나라도 빠지면 macOS 가 해당 해상도 슬롯에서 다른 크기를 늘려 쓰며 흐릿해진다.
    private static let expectedICNSEntries: [(type: String, pixels: UInt32)] = [
        ("icp4", 16),
        ("icp5", 32),
        ("ic11", 32),
        ("ic12", 64),
        ("ic07", 128),
        ("ic13", 256),
        ("ic08", 256),
        ("ic14", 512),
        ("ic09", 512),
    ]

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func resourceData(_ name: String) throws -> Data {
        let url = Self.resourcesDirectory.appendingPathComponent(name)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "아이콘 리소스가 없습니다: \(url.path) — `python3 macos/Scripts/make-icons.py` 로 생성하세요."
        )
        return try Data(contentsOf: url)
    }

    /// 빅엔디언 UInt32 읽기. `Data` 의 슬라이스 인덱스는 원본 기준이라 offset 을 명시적으로 더한다.
    private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        precondition(offset + 4 <= data.count)
        let base = data.startIndex + offset
        return (UInt32(data[base]) << 24)
            | (UInt32(data[base + 1]) << 16)
            | (UInt32(data[base + 2]) << 8)
            | UInt32(data[base + 3])
    }

    /// PNG IHDR 청크에서 (width, height) 를 읽는다. Foundation 만으로 충분하다.
    /// IHDR 은 규격상 시그니처(8B) 직후 첫 청크이고, 길이(4B)+타입(4B) 뒤 8바이트가 가로·세로다.
    private func pngDimensions(_ data: Data) throws -> (width: UInt32, height: UInt32) {
        try XCTSkipIf(data.count < 24, "PNG 가 IHDR 을 담기에도 너무 짧습니다 (\(data.count) bytes)")
        let chunkType = data.subdata(in: (data.startIndex + 12)..<(data.startIndex + 16))
        XCTAssertEqual(String(data: chunkType, encoding: .ascii), "IHDR", "첫 청크가 IHDR 이 아닙니다")
        return (readUInt32BE(data, at: 16), readUInt32BE(data, at: 20))
    }

    // MARK: - AppIcon.icns

    func testAppIconICNSHeaderIsWellFormed() throws {
        let data = try resourceData("AppIcon.icns")

        let magic = data.subdata(in: data.startIndex..<(data.startIndex + 4))
        XCTAssertEqual(String(data: magic, encoding: .ascii), "icns", "icns magic 이 아닙니다")

        // 헤더의 선언 길이와 실제 파일 크기가 어긋나면 Finder 가 아이콘을 통째로 무시한다.
        // (파일이 잘렸거나 엔트리를 손으로 덧붙였을 때 나는 전형적 증상)
        XCTAssertEqual(
            Int(readUInt32BE(data, at: 4)),
            data.count,
            "icns 헤더의 전체 길이 필드가 실제 파일 크기와 다릅니다"
        )
    }

    func testAppIconICNSContainsAllExpectedPNGEntries() throws {
        let data = try resourceData("AppIcon.icns")

        var found: [String: (size: Int, dimensions: (width: UInt32, height: UInt32))] = [:]
        var offset = 8

        while offset + 8 <= data.count {
            let typeData = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + 4))
            guard let type = String(data: typeData, encoding: .ascii) else {
                return XCTFail("offset \(offset): 엔트리 타입 코드가 ASCII 가 아닙니다")
            }

            let declared = Int(readUInt32BE(data, at: offset + 4))
            XCTAssertGreaterThan(declared, 8, "엔트리 '\(type)' 의 길이가 헤더(8B)보다 작습니다")
            XCTAssertLessThanOrEqual(
                offset + declared, data.count,
                "엔트리 '\(type)' 가 파일 끝을 넘어갑니다 — 파일이 잘렸습니다"
            )
            guard declared > 8, offset + declared <= data.count else { return }

            let payload = data.subdata(in: (data.startIndex + offset + 8)..<(data.startIndex + offset + declared))
            XCTAssertEqual(
                payload.prefix(8), Self.pngSignature,
                "엔트리 '\(type)' 가 PNG 시그니처로 시작하지 않습니다"
            )
            found[type] = (payload.count, try pngDimensions(payload))
            offset += declared
        }

        XCTAssertEqual(offset, data.count, "엔트리 길이 합이 파일 크기와 맞지 않습니다")

        for expected in Self.expectedICNSEntries {
            guard let entry = found[expected.type] else {
                XCTFail("icns 에 '\(expected.type)' 엔트리가 없습니다 (기대 \(expected.pixels)px)")
                continue
            }
            XCTAssertEqual(entry.dimensions.width, expected.pixels, "'\(expected.type)' 가로 크기 불일치")
            XCTAssertEqual(entry.dimensions.height, expected.pixels, "'\(expected.type)' 세로 크기 불일치")
            XCTAssertGreaterThan(entry.size, 100, "'\(expected.type)' 엔트리가 비정상적으로 작습니다")
        }
    }

    // MARK: - 메뉴 막대 아이콘

    func testMenuBarIconIs18x18() throws {
        let data = try resourceData("MenuBarIcon.png")
        XCTAssertEqual(data.prefix(8), Self.pngSignature, "PNG 시그니처가 아닙니다")

        let size = try pngDimensions(data)
        // 18pt 는 macOS 메뉴 막대 아이콘의 표준 크기다. 이보다 크면 잘리거나 막대를 밀어낸다.
        XCTAssertEqual(size.width, 18)
        XCTAssertEqual(size.height, 18)
    }

    func testMenuBarIconRetinaIsExactlyDouble() throws {
        let data = try resourceData("MenuBarIcon@2x.png")
        XCTAssertEqual(data.prefix(8), Self.pngSignature, "PNG 시그니처가 아닙니다")

        let size = try pngDimensions(data)
        // @2x 가 1x 의 정확히 2배가 아니면 AppKit 이 짝을 못 맞춰 Retina 에서 흐려진다.
        XCTAssertEqual(size.width, 36)
        XCTAssertEqual(size.height, 36)
    }

    /// 알파 채널 보존 확인 — 메뉴 막대 아이콘이 불투명하면 다크 모드에서 흰 사각형이 된다.
    /// IHDR 의 color type(바이트 25)이 6(truecolor+alpha) 또는 4(grayscale+alpha) 여야 한다.
    func testMenuBarIconsKeepAlphaChannel() throws {
        for name in Self.menuBarIconNames {
            let data = try resourceData(name)
            let colorType = data[data.startIndex + 25]
            XCTAssertTrue(
                colorType == 6 || colorType == 4,
                "\(name): 알파 없는 PNG color type \(colorType) — make-icons.py 가 RGBA 로 저장해야 합니다"
            )
        }
    }

    // MARK: - 메뉴 막대 template 불변식 (SOO-1325)
    //
    // 메뉴 막대 아이콘은 macOS template 이미지다 — 시스템이 **알파만** 읽고 색은 버린다.
    // 따라서 "그림"은 전적으로 알파 마스크에 들어 있고, 마스크가 망가지면 아이콘은 조용히
    // 무늬 없는 덩어리가 된다(컴파일도 통과하고 Linux 빌드도 통과한다). 아래 세 테스트가
    // Mac 없이 그 회귀를 잡는다. 실측 기준선: `Scripts/make-icons.py` 현재 산출물은
    // 18px 에서 알파 255 가 14% · 내부 knockout 10.8%, 36px 에서 22% · 15.8% 다.
    // 회귀 대상인 이전 컬러 PNG 는 두 크기 모두 내부 knockout 0.0% 였다.

    private static let menuBarIconNames = ["MenuBarIcon.png", "MenuBarIcon@2x.png"]

    /// template 은 색을 쓰지 않는다 — 색 채널이 남아 있으면 컬러 아이콘으로 되돌아간 것이다.
    func testMenuBarIconsCarryNoColor() throws {
        for name in Self.menuBarIconNames {
            let image = try PNGPixelReader.decode(try resourceData(name))
            XCTAssertTrue(image.hasAlpha, "\(name): 알파 채널이 없습니다 (color type \(image.colorType))")

            for y in 0..<image.height {
                for x in 0..<image.width {
                    let channels = image.colorChannels(x: x, y: y)
                    guard channels.allSatisfy({ $0 == 0 }) else {
                        return XCTFail(
                            "\(name): (\(x), \(y)) 의 색 채널이 \(Array(channels)) 입니다 — "
                                + "template 마스크는 모든 색 채널이 0 이어야 합니다"
                        )
                    }
                }
            }
        }
    }

    /// 이번 전환의 핵심 가드 — 알파가 전부 불투명하면 template 으로 칠했을 때 **덩어리**가 된다.
    /// 컬러 PNG 에 `isTemplate = true` 만 켜는 회귀가 정확히 이 모양으로 나타난다.
    func testMenuBarIconsAreNotFullyOpaqueBlobs() throws {
        for name in Self.menuBarIconNames {
            let image = try PNGPixelReader.decode(try resourceData(name))
            let total = image.width * image.height

            var opaque = 0
            var ink = 0
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let alpha = image.alpha(x: x, y: y)
                    if alpha == 255 { opaque += 1 }
                    if alpha >= 200 { ink += 1 }
                }
            }

            XCTAssertLessThan(
                opaque, total,
                "\(name): 모든 픽셀이 완전 불투명합니다 — 마스크가 아니라 통짜 이미지입니다"
            )
            // 반대 방향 회귀(마스크가 너무 옅어 아무것도 안 보임)도 같이 막는다.
            // 현재 실측 36%(18px) / 41%(36px) 이므로 25% 는 충분한 여유를 둔 하한이다.
            XCTAssertGreaterThan(
                ink, total / 4,
                "\(name): 진한 픽셀이 \(ink)/\(total) 뿐입니다 — 실루엣이 너무 옅어 메뉴 막대에서 보이지 않습니다"
            )
        }
    }

    /// 실루엣 **안쪽**이 뚫려 있어야 그림으로 읽힌다 — 흰 커서와 `한/영` 글자 자리다.
    /// 바깥 여백은 원래 투명하므로, 각 행에서 잉크의 좌우 끝 사이(=내부)만 센다.
    func testMenuBarIconsKeepInteriorKnockout() throws {
        for name in Self.menuBarIconNames {
            let image = try PNGPixelReader.decode(try resourceData(name))

            var interior = 0
            var knockout = 0
            for y in 0..<image.height {
                let inkColumns = (0..<image.width).filter { image.alpha(x: $0, y: y) >= 200 }
                guard let first = inkColumns.first, let last = inkColumns.last, last > first + 1 else { continue }

                for x in (first + 1)..<last {
                    interior += 1
                    if image.alpha(x: x, y: y) <= 96 { knockout += 1 }
                }
            }

            XCTAssertGreaterThan(interior, 0, "\(name): 잉크 영역을 찾지 못했습니다")
            // 실측 10.8%(18px) / 15.8%(36px). 이전 컬러 PNG 는 0.0% 였다.
            // 5% 는 두 값 모두에 여유를 두면서 "덩어리" 회귀는 확실히 걸러내는 하한이다.
            XCTAssertGreaterThan(
                knockout * 100, interior * 5,
                "\(name): 내부 투명 픽셀이 \(knockout)/\(interior) 뿐입니다 — "
                    + "커서와 `한/영` 이 메워져 덩어리로 보입니다"
            )
        }
    }

    // MARK: - 형태 단순화 불변식 (SOO-1326)
    //
    // 메뉴 막대 아이콘은 `한/영` 글자를 뺀 **커서 전용 실루엣**이다. 18px 에서 글자 획은
    // 1px 미만이라 반드시 뭉개지고, 이것은 파라미터가 아니라 형태의 문제였다(보더 실기
    // 확인, SOO-1319). 아래 두 테스트는 `한/영` 이 마스크로 되살아나는 회귀를 잡는다 —
    // 글자가 돌아오면 내부 뚫림이 여러 덩어리로 쪼개지기 때문이다.
    //
    // 실측: 직전 마스크(SOO-1325)는 @2x 내부 뚫림 덩어리가 13개(커서 1 + `한/영` 파편 12),
    // 현재 마스크는 1개다. 이 수치가 두 형태를 실제로 가른다.

    /// 알파 `< 64` 인 픽셀의 4-연결 연결요소 중 **이미지 테두리에 닿지 않는 것**의 크기 목록.
    ///
    /// 테두리에 닿는 덩어리는 원 바깥의 투명한 배경이므로 "뚫림"이 아니다. 나머지가
    /// 실루엣 안에 뚫린 구멍이다. 큰 것부터 정렬해 돌려준다.
    private func interiorHoleSizes(_ image: DecodedPNG, alphaThreshold: UInt8 = 64) -> [Int] {
        var visited = [Bool](repeating: false, count: image.width * image.height)
        var sizes: [Int] = []

        for startY in 0..<image.height {
            for startX in 0..<image.width {
                let startIndex = startY * image.width + startX
                guard !visited[startIndex], image.alpha(x: startX, y: startY) < alphaThreshold else { continue }

                // 반복(스택) flood fill — 재귀는 36x36 에서도 깊이가 1000 을 넘을 수 있다.
                var stack = [(startX, startY)]
                visited[startIndex] = true
                var size = 0
                var touchesBorder = false

                while let (x, y) = stack.popLast() {
                    size += 1
                    if x == 0 || y == 0 || x == image.width - 1 || y == image.height - 1 {
                        touchesBorder = true
                    }

                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, ny >= 0, nx < image.width, ny < image.height else { continue }
                        let index = ny * image.width + nx
                        guard !visited[index], image.alpha(x: nx, y: ny) < alphaThreshold else { continue }
                        visited[index] = true
                        stack.append((nx, ny))
                    }
                }

                if !touchesBorder { sizes.append(size) }
            }
        }

        return sizes.sorted(by: >)
    }

    /// @2x 의 내부 뚫림은 **커서 하나**여야 한다 — 여러 개면 `한/영` 이 되살아난 것이다.
    /// 그리고 그 하나가 충분히 커야 1x 로 줄여도 형태가 남는다.
    ///
    /// 엄격한 개수 판정을 @2x 에만 거는 이유: 18px 은 리샘플링 잔여로 1px 짜리 파편이
    /// 생길 수 있어(현재 마스크도 18px 에서는 2덩어리로 측정된다) 개수가 형태를 말해 주지
    /// 않는다. 36px 에서는 잔여가 커서에 흡수되어 깨끗이 1개로 떨어진다.
    func testRetinaMenuBarIconHasExactlyOneInteriorHole() throws {
        let image = try PNGPixelReader.decode(try resourceData("MenuBarIcon@2x.png"))
        let holes = interiorHoleSizes(image)

        XCTAssertEqual(
            holes.count, 1,
            "MenuBarIcon@2x.png: 내부 뚫림이 \(holes.count)개입니다(크기 \(holes)) — "
                + "커서 하나만 뚫려야 합니다. `한/영` 글자가 마스크로 되살아났는지 확인하세요."
        )
        // 실측 79px. 확대 없이 위치만 옮긴 안은 43px 이라 1x 에서 커서가 약했다.
        // 60 은 두 안을 가르면서 리샘플링 흔들림에는 여유를 둔 하한이다.
        XCTAssertGreaterThanOrEqual(
            holes.first ?? 0, 60,
            "MenuBarIcon@2x.png: 커서 구멍이 \(holes.first ?? 0)px 뿐입니다 — "
                + "36px 기준 60px 이상이어야 1x 로 줄여도 커서가 읽힙니다"
        )
    }

    /// 1x 는 개수 대신 **가장 큰 구멍의 크기**로 본다 — 커서가 18px 에서도 남아 있는지.
    /// 실측 16px. 직전 마스크는 7px 이었고, 그때 보더가 "뭉개져 안 읽힌다"고 보고했다.
    func testMenuBarIconKeepsLegibleCursorHoleAt1x() throws {
        let image = try PNGPixelReader.decode(try resourceData("MenuBarIcon.png"))
        let holes = interiorHoleSizes(image)

        XCTAssertGreaterThanOrEqual(
            holes.first ?? 0, 10,
            "MenuBarIcon.png: 가장 큰 내부 뚫림이 \(holes.first ?? 0)px 뿐입니다(전체 \(holes)) — "
                + "18px 에서 커서가 메워져 덩어리로 보입니다"
        )
    }
}
