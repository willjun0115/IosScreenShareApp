import Foundation
import WebRTC

class KAUMasterEncoder {
    static let shared = KAUMasterEncoder()
    
    // Key 포맷: "코덱 이름" (예: h264, vp8)
    private var realEncoders: [String: RTCVideoEncoder] = [:]
    private var callbacks: [String: [String: RTCVideoEncoderCallback]] = [:]
    private var isEngineStarted: [String: Bool] = [:]
    private let stateLock = NSLock()
    private var lastEncodedTimestampNs: [String: Int64] = [:]
    
    // I-frame 주기 제어용 변수 (예: 2초 = 2,000,000,000 ns)
    private var lastKeyframeTimestampNs: [String: Int64] = [:]
    private let keyframeIntervalNs: Int64 = 2_000_000_000
    
    init() {}
    
    func registerCallback(key: String, id: String, callback: @escaping RTCVideoEncoderCallback) {
        stateLock.lock()
        if callbacks[key] == nil { callbacks[key] = [:] }
        callbacks[key]?[id] = callback
        let count = callbacks[key]?.count ?? 0
        stateLock.unlock()
        NSLog("🔗 [Multiplexer] 콜백 연결 (Key: \(key), 프록시: \(id.prefix(4)), 현재 뷰어: \(count)명)")
    }
    
    // 실제 엔진 생성 시점을 startEncode 내부로 이동시켜 해상도 기반으로 격리 생성
    func startEncode(key: String, info: RTCVideoCodecInfo, settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        stateLock.lock()
        
        if realEncoders[key] == nil {
            NSLog("🛠️ [Multiplexer] 새 공유 인코더 생성 시도 (Key: \(key), Codec: \(info.name))")
            let encoder = RTCDefaultVideoEncoderFactory().createEncoder(info)
            if encoder == nil {
                NSLog("❌ [Multiplexer] 공유 인코더 생성 실패 (Key: \(key))")
            } else {
                NSLog("✅ [Multiplexer] 공유 인코더 생성 성공 (Key: \(key))")
            }
            realEncoders[key] = encoder
            isEngineStarted[key] = false
            
            encoder?.setCallback { [weak self] (encodedImage, codecInfo) -> Bool in
                guard let self = self else { return false }
                
                self.stateLock.lock()
                let currentCallbacks = Array((self.callbacks[key] ?? [:]).values)
                self.stateLock.unlock()
                
                for cb in currentCallbacks {
                    _ = cb(encodedImage, codecInfo)
                }
                return true
            }
        }
        
        let encoder = realEncoders[key]
        let alreadyStarted = isEngineStarted[key] ?? false
        
        // 처음 연결된 뷰어(프록시)일 때만 실제 하드웨어 엔진을 가동
        if !alreadyStarted {
            isEngineStarted[key] = true
            stateLock.unlock()
            
            let result = Int(encoder?.startEncode(with: settings, numberOfCores: numberOfCores) ?? -1)
            NSLog("🚀 [Multiplexer] 공유 인코더 엔진 최초 가동 결과: \(result) (Key: \(key))")
            return result
        } else {
            stateLock.unlock()
            // 두 번째 접속자 부터는 공유 인코더를 재가동하지 않고 0을 반환
            return 0
        }
    }
    
    func encode(key: String, frame: RTCVideoFrame, info: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        stateLock.lock()
        
        let nowNs = frame.timeStampNs
        let lastKeyNs = lastKeyframeTimestampNs[key] ?? 0
        
        // 정해진 간격이 지났는지 확인하고 I-frame 생성
        let shouldForceKeyframe = (nowNs - lastKeyNs) >= keyframeIntervalNs
        
        var modifiedFrameTypes: [NSNumber]
        if shouldForceKeyframe {
            modifiedFrameTypes = [NSNumber(value: RTCFrameType.videoFrameKey.rawValue)]
            lastKeyframeTimestampNs[key] = nowNs
            // NSLog("🔑 [Multiplexer] I-Frame 생성됨 (Key: \(key))")
        } else {
            // 외부에서 들어온 I-frame 요청을 무시하고 항상 Delta 프레임으로 처리
            modifiedFrameTypes = [NSNumber(value: RTCFrameType.videoFrameDelta.rawValue)]
        }
        
        if !shouldForceKeyframe && frame.timeStampNs == lastEncodedTimestampNs[key] {
            stateLock.unlock()
            return 0
        }
        lastEncodedTimestampNs[key] = frame.timeStampNs
        let encoder = realEncoders[key]
        stateLock.unlock()
        
        let result = Int(encoder?.encode(frame, codecSpecificInfo: info, frameTypes: modifiedFrameTypes) ?? -1)
        if result != 0 {
            NSLog("❌ [Multiplexer] 프레임 인코딩 실패! 결과코드: \(result) (Key: \(key))")
        }
        return result
    }
    
    func releaseProxy(key: String, id: String) -> Int {
        stateLock.lock()
        callbacks[key]?.removeValue(forKey: id)
        let count = callbacks[key]?.count ?? 0
        
        var result = 0
        if count == 0 {
            // 마지막 뷰어가 해제되면 공유 인코더도 메모리에서 해제
            NSLog("🛑 [Multiplexer] 공유 인코더 종료 (Key: \(key))")
            if let encoder = realEncoders[key] {
                result = Int(encoder.release())
            }
            realEncoders.removeValue(forKey: key)
            callbacks.removeValue(forKey: key)
            isEngineStarted.removeValue(forKey: key)
            lastEncodedTimestampNs.removeValue(forKey: key)
            lastKeyframeTimestampNs.removeValue(forKey: key)
        }
        stateLock.unlock()
        
        NSLog("🔽 [Multiplexer] 프록시 해제 (Key: \(key), 남은 뷰어: \(count)명)")
        return result
    }
    
    func setBitrate(key: String, bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        stateLock.lock()
        let encoder = realEncoders[key]
        stateLock.unlock()
        return encoder?.setBitrate(bitrateKbit, framerate: framerate) ?? 0
    }
    
    func scalingSettings(key: String) -> RTCVideoEncoderQpThresholds? {
        stateLock.lock()
        let encoder = realEncoders[key]
        stateLock.unlock()
        return encoder?.scalingSettings()
    }
    
    func implementationName() -> String {
        return "KAU_Multiplexer_Resolution_Aware"
    }
}
