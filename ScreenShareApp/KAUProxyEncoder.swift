import Foundation
import WebRTC

class KAUProxyEncoder: NSObject, RTCVideoEncoder {
    private let proxyId = UUID().uuidString
    private let codecInfo: RTCVideoCodecInfo
    
    private var activeEncoderKey: String?
    private var savedCallback: RTCVideoEncoderCallback?
        
    init(info: RTCVideoCodecInfo) {
        self.codecInfo = info
        super.init()
        NSLog("🕵️ [Proxy-\(info.name)-\(proxyId.prefix(4))] 생성됨")
    }
    
    func implementationName() -> String {
        return KAUMasterEncoder.shared.implementationName()
    }
    
    // ✨ 핵심: 마스터가 아직 생성되기 전이므로, 프록시가 WebRTC 엔진의 질문에 직접 하드코딩으로 대답합니다.
    var resolutionAlignment: Int {
        return codecInfo.name.lowercased() == "h264" ? 1 : 2
    }
    var applyAlignmentToAllSimulcastLayers: Bool { return false }
    var supportsNativeHandle: Bool {
        // H264는 CVPixelBuffer 직접 처리(true), VP8/VP9은 I420 변환 필요(false)
        return codecInfo.name.lowercased() == "h264"
    }
    
    func setCallback(_ callback: RTCVideoEncoderCallback?) {
        self.savedCallback = callback
        // 엔진 가동 중 콜백이 해제(nil)되면 마스터에서도 구독 해제
        if let key = activeEncoderKey {
            if let cb = callback {
                KAUMasterEncoder.shared.registerCallback(key: key, id: proxyId, callback: cb)
            } else {
                _ = KAUMasterEncoder.shared.releaseProxy(key: key, id: proxyId)
            }
        }
    }
    
    func startEncode(with settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        // ✨ 핵심: 코덱 이름에 가로/세로 해상도를 결합하여 독립적인 엔진 키 생성 (예: "vp8_720x1280")
        let key = "\(codecInfo.name.lowercased())_\(settings.width)x\(settings.height)"
        self.activeEncoderKey = key
        
        // 키가 생성되었으므로 대기 중이던 콜백을 마스터에 등록
        if let cb = savedCallback {
            KAUMasterEncoder.shared.registerCallback(key: key, id: proxyId, callback: cb)
        }
        
        return KAUMasterEncoder.shared.startEncode(key: key, info: codecInfo, settings: settings, numberOfCores: numberOfCores)
    }
        
    func encode(_ frame: RTCVideoFrame, codecSpecificInfo info: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        guard let key = activeEncoderKey else { return -1 }
        return KAUMasterEncoder.shared.encode(key: key, frame: frame, info: info, frameTypes: frameTypes)
    }
    
    func release() -> Int {
        guard let key = activeEncoderKey else { return 0 }
        return KAUMasterEncoder.shared.releaseProxy(key: key, id: proxyId)
    }
        
    func setBitrate(_ bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        guard let key = activeEncoderKey else { return 0 }
        return KAUMasterEncoder.shared.setBitrate(key: key, bitrateKbit: bitrateKbit, framerate: framerate)
    }
    
    func scalingSettings() -> RTCVideoEncoderQpThresholds? {
        guard let key = activeEncoderKey else { return nil }
        return KAUMasterEncoder.shared.scalingSettings(key: key)
    }
}
