//
//  BackgroundAudioPlayer.swift
//  ScreenShareApp
//

import Foundation
import AVFoundation

class BackgroundAudioPlayer {
    static let shared = BackgroundAudioPlayer()
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private init() {}
    
    func start() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // mixWithOthers 옵션 - 다른 앱의 소리를 끄지 않음
            try audioSession.setCategory(.playback, options: .mixWithOthers)
            try audioSession.setActive(true)
            
            audioEngine.attach(playerNode)
            let format = audioEngine.outputNode.outputFormat(forBus: 0)
            audioEngine.connect(playerNode, to: audioEngine.outputNode, format: format)
            
            try audioEngine.start()
            
            // 무음(Silence) 버퍼 생성
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else { return }
            buffer.frameLength = 1024
            
            // 버퍼 데이터를 모두 0.0으로 채움 (완벽한 무음)
            if let floatChannelData = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        floatChannelData[channel][frame] = 0.0
                    }
                }
            }
            
            // 무한 루프 재생
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            playerNode.play()
            
            NSLog("✅ [Background] 무음 오디오 재생 시작 (백그라운드 모드 활성화)")
        } catch {
            NSLog("❌ [Background] 오디오 세션 초기화 실패: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        playerNode.stop()
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        NSLog("🛑 [Background] 무음 오디오 재생 종료")
    }
}
