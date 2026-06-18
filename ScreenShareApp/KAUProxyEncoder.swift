import Foundation
import WebRTC

class KAUProxyEncoder: NSObject, RTCVideoEncoder {
    private let proxyId = UUID().uuidString
    private let codecKey: String
        
    init(codecKey: String) {
        self.codecKey = codecKey
        super.init()
        NSLog("🕵️ [Proxy-\(codecKey)-\(proxyId.prefix(4))] 생성됨")
    }
    
    func implementationName() -> String {
        return KAUMasterEncoder.shared.implementationName()
    }
    
    var resolutionAlignment: Int {
        return KAUMasterEncoder.shared.resolutionAlignment(for: codecKey)
    }
    var applyAlignmentToAllSimulcastLayers: Bool {
        return KAUMasterEncoder.shared.applyAlignmentToAllSimulcastLayers(for: codecKey)
    }
    var supportsNativeHandle: Bool {
        return KAUMasterEncoder.shared.supportsNativeHandle(for: codecKey)
    }
    
    func setCallback(_ callback: RTCVideoEncoderCallback?) {
        guard let callback = callback else {
            NSLog("⚠️ [Proxy-\(proxyId.prefix(4))] Callback is nil. 프록시 해제 요청으로 간주합니다.")
            _ = KAUMasterEncoder.shared.releaseProxy(codecKey: codecKey, id: proxyId)
            return
        }
        
        KAUMasterEncoder.shared.registerCallback(codecKey: codecKey, id: proxyId, callback: callback)
    }
        
    func encode(_ frame: RTCVideoFrame, codecSpecificInfo info: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        return KAUMasterEncoder.shared.encode(codecKey: codecKey, frame: frame, info: info, frameTypes: frameTypes)
    }
    
    func release() -> Int {
        return KAUMasterEncoder.shared.releaseProxy(codecKey: codecKey, id: proxyId)
    }
    
    func startEncode(with settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        return KAUMasterEncoder.shared.startEncode(codecKey: codecKey, settings: settings, numberOfCores: numberOfCores)
    }
        
    func setBitrate(_ bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        return KAUMasterEncoder.shared.setBitrate(codecKey: codecKey, bitrateKbit: bitrateKbit, framerate: framerate)
    }
    
    func scalingSettings() -> RTCVideoEncoderQpThresholds? {
        return KAUMasterEncoder.shared.scalingSettings(codecKey: codecKey)
    }
}
