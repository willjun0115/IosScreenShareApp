import Foundation
import WebRTC

class KAUEncoderFactory: NSObject, RTCVideoEncoderFactory {
    private let defaultFactory = RTCDefaultVideoEncoderFactory()
    private var allCodecs: [RTCVideoCodecInfo] = []
    
    // 우선 사용할 코덱 이름 (예: "vp8", "h264")
    private let preferredCodecName = "vp8"

    override init() {
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
        // 코덱 메타데이터만 프록시로 전달하고 생성 위임
        return KAUProxyEncoder(info: info)
    }
}
