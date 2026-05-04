//
//  RTCEncoderFactory.swift
//  ScreenShareApp
//
//  Created by supercoder on 4/23/26.
//

import Foundation
import WebRTC

class RTCEncoderFactory: NSObject, RTCVideoEncoderFactory {
    private let defaultFactory = RTCDefaultVideoEncoderFactory()
    
    func supportedCodecs() -> [RTCVideoCodecInfo] {
        let allCodecs = defaultFactory.supportedCodecs()
        
        // 대소문자 구분 없이 "h264"가 포함된 모든 코덱을 찾습니다.
        let h264Codecs = allCodecs.filter {
            $0.name.localizedCaseInsensitiveContains("h264")
        }
        
        // 만약 필터링 결과가 비어있다면, 전체 목록을 반환
        if h264Codecs.isEmpty {
            return allCodecs
        }
        
        // h264가 발견되었다면, 필터링한 결과를 반환
        return h264Codecs
    }
    
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        return defaultFactory.createEncoder(info)
    }
}
