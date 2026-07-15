import Foundation
import WebRTC

class KAUEncoderFactory: NSObject, RTCVideoEncoderFactory {
    private let defaultFactory = RTCDefaultVideoEncoderFactory()
    private var allCodecs: [RTCVideoCodecInfo] = []
    
    // 우선 사용할 코덱 이름 (예: "vp8", "h264")
    private let preferredCodecName: String

    init(preferredCodec: String = "H264") {
        self.preferredCodecName = preferredCodec.lowercased()
        super.init()
        allCodecs = defaultFactory.supportedCodecs()
        
        NSLog("[EncoderFactory] 지원 코덱 목록 (총 \(allCodecs.count)개)")
        for (index, codec) in allCodecs.enumerated() {
            NSLog("   \(index + 1). \(codec.name)")
        }
    }

    func supportedCodecs() -> [RTCVideoCodecInfo] {
        let preferredCodecs = allCodecs.filter { $0.name.lowercased() == preferredCodecName }
        let otherCodecs = allCodecs.filter { $0.name.lowercased() != preferredCodecName }
        return preferredCodecs + otherCodecs
    }
    
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        if info.name.lowercased() == "h264" {
            // H264 하드웨어 인코더는 자원 제한이 있으므로 프록시/마스터 공유 구조 사용
            return KAUProxyEncoder(info: info)
        } else {
            // VP8, VP9 등 소프트웨어 코덱은 C++ 래퍼 제약이 있고 자원 제한이 없으므로 기본 인코더를 직접 생성해 리턴
            NSLog("🛠️ [EncoderFactory] 소프트웨어 코덱 기본 인코더 직접 생성 (Codec: \(info.name))")
            return defaultFactory.createEncoder(info)
        }
    }
}
