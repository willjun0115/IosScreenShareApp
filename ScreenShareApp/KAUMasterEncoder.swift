import Foundation
import WebRTC

class KAUMasterEncoder {
    static let shared = KAUMasterEncoder()
    
    private var realEncoder: RTCVideoEncoder?
    private var callbacks: [String: RTCVideoEncoderCallback] = [:]
    private let stateLock = NSLock()
    
    private var lastEncodedTimestampNs: Int64 = 0
    private var isHardwareStarted = false
    
    init() {}
    
    // 1. 하드웨어 인코더 최초 생성
    func setupMaster(info: RTCVideoCodecInfo) {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        if realEncoder == nil {
            realEncoder = RTCDefaultVideoEncoderFactory().createEncoder(info)
            
            realEncoder?.setCallback { [weak self] (encodedImage, info, header) -> Bool in
                guard let self = self else { return false }
                
                // 콜백을 뿌릴 때만 락을 잡아 명단을 복사
                self.stateLock.lock()
                let currentCallbacks = Array(self.callbacks.values)
                self.stateLock.unlock()
                
                // 콜백 목록에 인코딩된 이미지를 전달
                for cb in currentCallbacks {
                    _ = cb(encodedImage, info, header)
                }
                return true
            }
            NSLog("🛠️ [Multiplexer] 하드웨어 인코더 메모리 할당 완료")
        }
    }
    
    func registerCallback(id: String, callback: @escaping RTCVideoEncoderCallback) {
        stateLock.lock()
        callbacks[id] = callback
        let count = callbacks.count
        stateLock.unlock()
        NSLog("🔗 [Multiplexer] 프록시(\(id.prefix(4))) 콜백 연결 (현재 시청자: \(count)명)")
    }
    
    // 2. 엔진 가동 (최초 1회만 진짜 가동, 나머진 패스)
    func startEncode(settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        stateLock.lock()
        let encoder = realEncoder
        let alreadyStarted = isHardwareStarted
        if !alreadyStarted {
            isHardwareStarted = true
        }
        stateLock.unlock() // ✨ 반드시 락을 풀고 하드웨어에 접근!
        
        if !alreadyStarted {
            NSLog("🚀 [Multiplexer] 하드웨어 인코더 엔진 가동!")
            return Int(encoder?.startEncode(with: settings, numberOfCores: numberOfCores) ?? -1)
        }
        return 0
    }
    
    // 3. 인코딩 처리 (중복 방지)
    func encode(frame: RTCVideoFrame, info: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        stateLock.lock()
        if frame.timeStampNs == lastEncodedTimestampNs {
            stateLock.unlock()
            return 0
        }
        lastEncodedTimestampNs = frame.timeStampNs
        let encoder = realEncoder
        stateLock.unlock()
        
        return Int(encoder?.encode(frame, codecSpecificInfo: info, frameTypes: frameTypes) ?? -1)
    }
    
    // ✨ 핵심: 4. 프록시 해제 (진짜 인코더는 끄지 않음)
    func releaseProxy(id: String) -> Int {
        stateLock.lock()
        callbacks.removeValue(forKey: id) // 명단에서만 빼버립니다. (콜백 선 긋기)
        let count = callbacks.count
        stateLock.unlock()
        
        NSLog("🔽 [Multiplexer] 프록시(\(id.prefix(4))) 연결 해제 (남은 시청자: \(count)명)")
        // ✨ 하드웨어 인코더(realEncoder)를 절대 release 하지 않고 그대로 살려둡니다.
        return 0
    }
    
    func setBitrate(bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        stateLock.lock()
        let encoder = realEncoder
        stateLock.unlock()
        return encoder?.setBitrate(bitrateKbit, framerate: framerate) ?? 0
    }
    
    func scalingSettings() -> RTCVideoEncoderQpThresholds? {
        stateLock.lock()
        let encoder = realEncoder
        stateLock.unlock()
        return encoder?.scalingSettings()
    }
    
    func implementationName() -> String {
        return "KAU_Multiplexer_Final"
    }
}
