import Foundation
import WebRTC

class KAUMasterEncoder {
    static let shared = KAUMasterEncoder()
    
    private var realEncoders: [String: RTCVideoEncoder] = [:]
    private var callbacks: [String: [String: RTCVideoEncoderCallback]] = [:]
    private let stateLock = NSLock()
    private var lastEncodedTimestampNs: [String: Int64] = [:]
    
    func resolutionAlignment(for codecKey: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Int(realEncoders[codecKey]?.resolutionAlignment ?? 1)
    }
    
    func applyAlignmentToAllSimulcastLayers(for codecKey: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return realEncoders[codecKey]?.applyAlignmentToAllSimulcastLayers ?? false
    }
    
    func supportsNativeHandle(for codecKey: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return realEncoders[codecKey]?.supportsNativeHandle ?? false
    }
    
    init() {}
    
    // 1. 하드웨어 인코더 최초 생성
    func setupMaster(info: RTCVideoCodecInfo, codecKey: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        if realEncoders[codecKey] == nil {
            let encoder = RTCDefaultVideoEncoderFactory().createEncoder(info)
            realEncoders[codecKey] = encoder
            callbacks[codecKey] = [:]
            
            encoder?.setCallback { [weak self] (encodedImage, codecInfo) -> Bool in
                guard let self = self else { return false }
                
                self.stateLock.lock()
                let codecCallbacks = self.callbacks[codecKey] ?? [:]
                let currentCallbacks = Array(codecCallbacks.values)
                self.stateLock.unlock()
                
                for cb in currentCallbacks {
                    _ = cb(encodedImage, codecInfo)
                }
                return true
            }
        }
    }
    
    func registerCallback(codecKey: String, id: String, callback: @escaping RTCVideoEncoderCallback) {
        stateLock.lock()
        callbacks[codecKey]?[id] = callback
        let count = callbacks[codecKey]?.count ?? 0
        stateLock.unlock()
        NSLog("🔗 [Multiplexer] 프록시(\(id.prefix(4))) 콜백 연결 (현재 시청자: \(count)명)")
    }
    
    // 2. 엔진 가동 (최초 1회만 진짜 가동, 나머진 패스)
    func startEncode(codecKey: String, settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        stateLock.lock()
        let encoder = realEncoders[codecKey]
        stateLock.unlock()
        
        NSLog("🚀 [Multiplexer] 인코더 설정 업데이트 (Width: \(settings.width), Height: \(settings.height))")
        
        return Int(encoder?.startEncode(with: settings, numberOfCores: numberOfCores) ?? -1)
    }
    
    // 3. 인코딩 처리 (중복 방지)
    func encode(codecKey: String, frame: RTCVideoFrame, info: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        // 전달된 frameTypes에 KeyFrame 요청이 포함되어 있는지 확인
        let isKeyFrame = frameTypes.contains { type in
            RTCFrameType(rawValue: UInt(type.intValue)) == .videoFrameKey
        }
        
        stateLock.lock()
        if !isKeyFrame && frame.timeStampNs == lastEncodedTimestampNs[codecKey] {
            stateLock.unlock()
            return 0
        }
        lastEncodedTimestampNs[codecKey] = frame.timeStampNs
        let encoder = realEncoders[codecKey]
        stateLock.unlock()
        
        return Int(encoder?.encode(frame, codecSpecificInfo: info, frameTypes: frameTypes) ?? -1)
    }
    
    // 4. 프록시 해제
    func releaseProxy(codecKey: String, id: String) -> Int {
        stateLock.lock()
        callbacks[codecKey]?.removeValue(forKey: id)
        let count = callbacks[codecKey]?.count ?? 0
        stateLock.unlock()
        
        NSLog("🔽 [Multiplexer] 프록시(\(id.prefix(4))) 연결 해제 (남은 시청자: \(count)명)")
        return 0
    }
    
    func setBitrate(codecKey: String, bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        stateLock.lock()
        let encoder = realEncoders[codecKey]
        stateLock.unlock()
        return encoder?.setBitrate(bitrateKbit, framerate: framerate) ?? 0
    }
    
    func scalingSettings(codecKey: String) -> RTCVideoEncoderQpThresholds? {
        stateLock.lock()
        let encoder = realEncoders[codecKey]
        stateLock.unlock()
        return encoder?.scalingSettings()
    }
    
    func implementationName() -> String {
        return "KAU_Multiplexer_Final"
    }
}
