import Foundation
import Compression

/// 앱 번들에 내장된 Cyclemeter 시드(gzip JSON)를 RideRecord 배열로 로드한다.
/// 트랙(GPS 경로)까지 포함된 정제 데이터가 앱의 기본 기록이 된다.
enum SeedRides {
    static func load() -> [RideRecord] {
        let url = Bundle.main.url(forResource: "SeedRides", withExtension: "json.gz")
            ?? Bundle.main.url(forResource: "SeedRides.json", withExtension: "gz")
        guard let url, let gz = try? Data(contentsOf: url), let json = gunzip(gz) else { return [] }
        return (try? JSONDecoder().decode([RideRecord].self, from: json)) ?? []
    }

    /// gzip(표준 10바이트 헤더, FLG=0) 데이터를 원본으로 해제. 실패 시 nil.
    /// 본문(raw DEFLATE)을 Compression(COMPRESSION_ZLIB)으로 디코드한다.
    private static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08, bytes[3] == 0 else { return nil }
        // 마지막 4바이트(ISIZE, little-endian) = 원본 크기 mod 2^32
        let n = bytes.count
        let isize = Int(UInt32(bytes[n-4]) | (UInt32(bytes[n-3]) << 8) | (UInt32(bytes[n-2]) << 16) | (UInt32(bytes[n-1]) << 24))
        guard isize > 0 else { return nil }
        let body = Array(bytes[10..<(n-8)])   // 헤더 10 + 트레일러 8 제외 = raw DEFLATE
        var dst = [UInt8](repeating: 0, count: isize)
        let decoded = body.withUnsafeBufferPointer { src in
            dst.withUnsafeMutableBufferPointer { dstP in
                compression_decode_buffer(dstP.baseAddress!, isize, src.baseAddress!, body.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard decoded > 0 else { return nil }
        return Data(dst[0..<decoded])
    }
}
