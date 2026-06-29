//
//  KAUMacScreenCapturer.swift
//  ScreenShareApp
//

import Foundation
import CoreMedia
import WebRTC

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit

@available(macOS 12.3, iOS 18.0, macCatalyst 18.2, *)
class KAUMacScreenCapturer: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var rtcManager: WebRTCManager?
    
    func startCapture(rtcManager: WebRTCManager) {
        self.rtcManager = rtcManager
        
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self else { return }
            guard let content = content, error == nil else {
                NSLog("❌ [ScreenCaptureKit] 콘텐츠 가져오기 실패: \(String(describing: error))")
                return
            }
            
            // 첫 번째 디스플레이 캡처
            guard let display = content.displays.first else {
                NSLog("❌ [ScreenCaptureKit] 디스플레이를 찾을 수 없습니다.")
                return
            }
            
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = true
            
            self.stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            
            let queue = DispatchQueue(label: "com.screenshare.capturequeue")
            try? self.stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            
            self.stream?.startCapture { error in
                if let error = error {
                    NSLog("❌ [ScreenCaptureKit] 캡처 시작 실패: \(error)")
                } else {
                    NSLog("✅ [ScreenCaptureKit] 캡처 시작 성공")
                }
            }
        }
    }
    
    func stopCapture() {
        stream?.stopCapture { error in
            if let error = error {
                NSLog("❌ [ScreenCaptureKit] 캡처 중지 실패: \(error)")
            } else {
                NSLog("✅ [ScreenCaptureKit] 캡처 중지 성공")
            }
        }
        stream = nil
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        // SCStreamOutput에서 제공하는 sampleBuffer는 보통 CVPixelBuffer를 포함
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // CMSampleBuffer의 타임스탬프를 WebRTC 전송 포맷으로 변환
        let timeStampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000)
        
        rtcManager?.sendPixelBuffer(pixelBuffer, timeStampNs: timeStampNs)
    }
}
#endif
