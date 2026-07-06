import Foundation
import WebRTC

class KAUMasterEncoder {
    static let shared = KAUMasterEncoder()
    
    // Key는 "코덱_가로x세로"
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
            NSLog("🛠️ [Multiplexer] 새 실제 인코더 생성 (Key: \(key))")
            let encoder = RTCDefaultVideoEncoderFactory().createEncoder(info)
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
        stateLock.unlock()
        
        // 처음 연결된 뷰어(프록시)일 때만 실제 하드웨어 엔진에 시동을 겁니다.
        if !alreadyStarted {
            isEngineStarted[key] = true
            stateLock.unlock()
            
            NSLog("🚀 [Multiplexer] 실제 인코더 엔진 최초 가동 완료 (Key: \(key))")
            return Int(encoder?.startEncode(with: settings, numberOfCores: numberOfCores) ?? -1)
        } else {
            stateLock.unlock()
            // 두 번째 접속자(맥 등)부터는 하드웨어 인코더를 재가동하지 않고
            // WebRTC 규격상 성공(0)을 반환하여 C++ 엔진의 크래시를 원천 차단합니다.
            return 0
        }
    }
    
    func encode(key: String, frame: RTCVideoFrame, info: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        stateLock.lock()
        
        let nowNs = frame.timeStampNs
        let lastKeyNs = lastKeyframeTimestampNs[key] ?? 0
        
        // 정해진 간격(예: 2초)이 지났는지 확인하여 강제 I-frame 여부 결정
        let shouldForceKeyframe = (nowNs - lastKeyNs) >= keyframeIntervalNs
        
        var modifiedFrameTypes: [NSNumber]
        if shouldForceKeyframe {
            modifiedFrameTypes = [NSNumber(value: RTCFrameType.videoFrameKey.rawValue)]
            lastKeyframeTimestampNs[key] = nowNs
            // NSLog("🔑 [Multiplexer] 주기적 I-Frame 강제 생성 (Key: \(key))")
        } else {
            // 외부(Peer)에서 들어온 I-frame 요청(PLI/FIR)을 무시하고 항상 Delta 프레임으로 처리
            modifiedFrameTypes = [NSNumber(value: RTCFrameType.videoFrameDelta.rawValue)]
        }
        
        if !shouldForceKeyframe && frame.timeStampNs == lastEncodedTimestampNs[key] {
            stateLock.unlock()
            return 0
        }
        lastEncodedTimestampNs[key] = frame.timeStampNs
        let encoder = realEncoders[key]
        stateLock.unlock()
        
        return Int(encoder?.encode(frame, codecSpecificInfo: info, frameTypes: modifiedFrameTypes) ?? -1)
    }
    
    func releaseProxy(key: String, id: String) -> Int {
        stateLock.lock()
        callbacks[key]?.removeValue(forKey: id)
        let count = callbacks[key]?.count ?? 0
        
        var result = 0
        if count == 0 {
            // 마지막 뷰어가 해제되면 실제 하드웨어 인코더도 메모리에서 해제
            NSLog("🛑 [Multiplexer] 마지막 뷰어 해제됨. 실제 인코더 종료 (Key: \(key))")
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
