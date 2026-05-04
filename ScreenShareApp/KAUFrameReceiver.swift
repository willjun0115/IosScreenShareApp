//
//  KAUFrameReceiver.swift
//  ScreenShareApp
//
//  Created by supercoder on 5/4/26.
//

import Foundation
import CoreVideo
import QuartzCore

class KAUReceiver {
    static let shared = KAUReceiver()
    private var fileDescriptor: Int32 = -1
    private var mappedMemory: UnsafeMutableRawPointer?
    private let mappedSize = MemoryLayout<SharedFrameBuffer>.size + Int(MAX_FRAME_SIZE)
//    private var displayLink: CADisplayLink?
    private var rtcManager: WebRTCManager?
    private var pollingTimer: DispatchSourceTimer?
    private let pollingQueue = DispatchQueue(label: "com.will115.screenshare.polling", qos: .userInteractive)
    
    // 재사용할 픽셀 버퍼 풀
    private var pixelBufferPool: CVPixelBufferPool?

    func startReceiving(rtcManager: WebRTCManager) {
        // 수신 시작하기 전에 한 번 종료.
        stopReceiving()
        
        self.rtcManager = rtcManager
        guard let fileURL = SharedContext.bufferFileURL else { return }
        
        fileDescriptor = open(fileURL.path, O_RDWR, S_IRUSR | S_IWUSR)
        if fileDescriptor == -1 {
            NSLog("⚠️ [MAIN] 공유 파일 열기 실패. 아직 익스텐션이 생성하지 않았을 수 있습니다.")
            // 여기서는 실패하더라도 DisplayLink는 돌려야 익스텐션이 나중에 파일을 만들었을 때 읽을 수 있습니다.
        } else {
            mappedMemory = mmap(nil, mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, fileDescriptor, 0)
        }
        
//        displayLink = CADisplayLink(target: self, selector: #selector(pollBuffer))
//        displayLink?.preferredFramesPerSecond = 30 // 30fps 폴링
//        displayLink?.add(to: .main, forMode: .common)
        
        // 초당 30프레임(약 33ms 주기)으로 백그라운드 스레드에서 반복 실행
        pollingTimer = DispatchSource.makeTimerSource(queue: pollingQueue)
        pollingTimer?.schedule(deadline: .now(), repeating: .milliseconds(33))
        pollingTimer?.setEventHandler { [weak self] in
            self?.pollBuffer()
        }
        pollingTimer?.resume()
    }

    @objc private func pollBuffer() {
        autoreleasepool {
            // 아직 파일이 없어서 mmap이 안 된 경우 재시도
            if mappedMemory == nil || mappedMemory == MAP_FAILED {
                guard let fileURL = SharedContext.bufferFileURL else { return }
                fileDescriptor = open(fileURL.path, O_RDWR, S_IRUSR | S_IWUSR)
                if fileDescriptor != -1 {
                    mappedMemory = mmap(nil, mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, fileDescriptor, 0)
                    NSLog("✅ [MAIN] 지연된 mmap 성공")
                }
                return
            }
            
            guard let mappedMem = mappedMemory else { return }
            let headerPtr = mappedMem.bindMemory(to: SharedFrameBuffer.self, capacity: 1)
            
            // 익스텐션이 새 프레임을 썼는지 확인
            if headerPtr.pointee.isReady {
                headerPtr.pointee.isReady = false // 메인 앱이 읽기 시작함을 표시
                
                let width = Int(headerPtr.pointee.width)
                let height = Int(headerPtr.pointee.height)
                let format = headerPtr.pointee.pixelFormat
                
                // CVPixelBufferPool 초기화 (최초 1회 또는 해상도 변경 시)
                if pixelBufferPool == nil {
                    let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
                    let bufferAttributes: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: format,
                        kCVPixelBufferWidthKey as String: width,
                        kCVPixelBufferHeightKey as String: height,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:] // 빈 딕셔너리로 IOSurface 백업 활성화
                    ]
                    CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &pixelBufferPool)
                }
                
                var pixelBuffer: CVPixelBuffer?
                guard let pool = pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess, let pb = pixelBuffer else { return }
                
                CVPixelBufferLockBaseAddress(pb, [])
                
                // 데이터 복원
                let ySize = Int(headerPtr.pointee.yPlaneSize)
                let uvSize = Int(headerPtr.pointee.uvPlaneSize)
                let dataPtr = mappedMem.advanced(by: MemoryLayout<SharedFrameBuffer>.size)
                
                let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0)
                memcpy(yBase, dataPtr, ySize)
                
                let uvBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1)
                memcpy(uvBase, dataPtr.advanced(by: ySize), uvSize)
                
                CVPixelBufferUnlockBaseAddress(pb, [])
                
                // WebRTC 전송
                rtcManager?.sendPixelBuffer(pb, timeStampNs: headerPtr.pointee.timeStampNs)
                // NSLog("✅ [MAIN] mmap 프레임 수신 & 전송 완료")
            }
        }
    }

    func stopReceiving() {
//        displayLink?.invalidate()
//        displayLink = nil
        pollingTimer?.cancel()
        pollingTimer = nil
        
        if mappedMemory != nil && mappedMemory != MAP_FAILED {
            munmap(mappedMemory, mappedSize)
        }
        if fileDescriptor != -1 {
            close(fileDescriptor)
        }
        mappedMemory = nil
        fileDescriptor = -1
        pixelBufferPool = nil
    }
}
