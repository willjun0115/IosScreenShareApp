//
//  RTCEncoderFactory.swift
//  ScreenShareApp
//
//
import Foundation
import WebRTC

class KAUEncoderFactory: NSObject, RTCVideoEncoderFactory {
    private let defaultFactory = RTCDefaultVideoEncoderFactory()
    // private var filteredCodecs: [RTCVideoCodecInfo] = []
    private var allCodecs: [RTCVideoCodecInfo] = []
    private let preferredCodecName = "vp8"

    override init() {
        super.init()
        // 지원하는 전체 코덱 목록 수집
        allCodecs = defaultFactory.supportedCodecs()
        
        NSLog("📡 [KAUEncoderFactory] 지원 코덱 목록 (총 \(allCodecs.count)개)")
        for (index, codec) in allCodecs.enumerated() {
            var paramString = ""
            for (key, value) in codec.parameters {
                paramString += "[\(key): \(value)] "
            }
            NSLog("   \(index + 1). \(codec.name) | 파라미터: \(paramString.isEmpty ? "없음" : paramString)")
        }
                
        // H.264 코덱 필터링
        // self.filteredCodecs = allCodecs.filter { $0.name.lowercased() == "h264" }
    }

    func supportedCodecs() -> [RTCVideoCodecInfo] {
        // preferredCodecs를 앞에 배치하도록 코덱 목록 재배열
        let preferredCodecs = allCodecs.filter { $0.name.lowercased() == preferredCodecName }
        let otherCodecs = allCodecs.filter { $0.name.lowercased() != preferredCodecName }
        return preferredCodecs + otherCodecs
        // return filteredCodecs
    }
    
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        let codecKey = info.name.lowercased()
        KAUMasterEncoder.shared.setupMaster(info: info, codecKey: codecKey)
        return KAUProxyEncoder(codecKey: codecKey)
    }
}
