import Foundation
import WebRTC

class KAUProxyEncoder: NSObject, RTCVideoEncoder {
    private let proxyId = UUID().uuidString
    
    override init() {
        super.init()
        NSLog("🕵️ [Proxy-\(proxyId.prefix(4))] 생성됨")
    }
    
    func setCallback(_ callback: @escaping RTCVideoEncoderCallback) {
        KAUMasterEncoder.shared.registerCallback(id: proxyId, callback: callback)
    }
        
    func encode(_ frame: RTCVideoFrame, codecSpecificInfo info: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        return KAUMasterEncoder.shared.encode(frame: frame, info: info, frameTypes: frameTypes)
    }
        
    // ✨ WebRTC가 프록시를 부수면, 마스터에게 '콜백 줄만 끊어달라'고 요청합니다.
    func release() -> Int {
        return KAUMasterEncoder.shared.releaseProxy(id: proxyId)
    }
    
    func startEncode(with settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        return KAUMasterEncoder.shared.startEncode(settings: settings, numberOfCores: numberOfCores)
    }
        
    func setBitrate(_ bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        return KAUMasterEncoder.shared.setBitrate(bitrateKbit: bitrateKbit, framerate: framerate)
    }
    
    func scalingSettings() -> RTCVideoEncoderQpThresholds? {
        return KAUMasterEncoder.shared.scalingSettings()
    }
        
    func implementationName() -> String {
        return KAUMasterEncoder.shared.implementationName()
    }
}
