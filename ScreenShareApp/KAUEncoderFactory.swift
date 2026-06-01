//
//  RTCEncoderFactory.swift
//  ScreenShareApp
//
//
import Foundation
import WebRTC

class KAUEncoderFactory: NSObject, RTCVideoEncoderFactory {
    private let defaultFactory = RTCDefaultVideoEncoderFactory()
    private var filteredCodecs: [RTCVideoCodecInfo] = []

    override init() {
        super.init()
        // 지원하는 전체 코덱 목록 수집
        let allCodecs = defaultFactory.supportedCodecs()
        
        NSLog("📡 [KAUEncoderFactory] 지원 코덱 목록 (총 \(allCodecs.count)개)")
        for (index, codec) in allCodecs.enumerated() {
            var paramString = ""
            for (key, value) in codec.parameters {
                paramString += "[\(key): \(value)] "
            }
            NSLog("   \(index + 1). \(codec.name) | 파라미터: \(paramString.isEmpty ? "없음" : paramString)")
        }
                
        // H.264 코덱 필터링
        self.filteredCodecs = allCodecs.filter { $0.name.lowercased() == "h264" }
        
        // H.264 필터링 결과가 빈 배열일 경우 전체 코덱 목록 반환
        if self.filteredCodecs.isEmpty {
            NSLog("⚠️ [KAUEncoderFactory] H.264 코덱을 찾을 수 없습니다.")
            self.filteredCodecs = allCodecs
        }
    }

    func supportedCodecs() -> [RTCVideoCodecInfo] {
        let allCodecs = defaultFactory.supportedCodecs()
        // return allCodecs
        return filteredCodecs
    }
    
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        let codecName = info.name.lowercased()
                
        // H.264 요청 시 프록시(멀티플렉서) 인코더 반환
        if codecName.contains("h264") {
            KAUMasterEncoder.shared.setupMaster(info: info)
            return KAUProxyEncoder()
        }
        // 그 외 코덱 요청 시 WebRTC 기본 인코더 반환
        else {
            NSLog("webRTC default encoder 생성됨.")
            return defaultFactory.createEncoder(info)
        }
    }
}
