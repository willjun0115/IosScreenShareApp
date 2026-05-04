// SampleHandler.swift
import ReplayKit

// 디버그 로깅용 함수
func writeLog(_ message: String) {
    let defaults = UserDefaults(suiteName: "group.com.will115.screenshare")
    var logs = defaults?.stringArray(forKey: "ExtLogs") ?? []
    
    // 타임스탬프와 함께 로그 추가
    let time = Date().description
    logs.append("[\(time)] \(message)")
    
    // 로그가 너무 길어지지 않게 최근 20개만 유지
    if logs.count > 20 { logs.removeFirst() }
    
    defaults?.setValue(logs, forKey: "ExtLogs")
}

class SampleHandler: RPBroadcastSampleHandler {
    private var fileDescriptor: Int32 = -1
    private var mappedMemory: UnsafeMutableRawPointer?
    private let mappedSize = MemoryLayout<SharedFrameBuffer>.size + Int(MAX_FRAME_SIZE)

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        writeLog("Broadcast started")
        guard let fileURL = SharedContext.bufferFileURL else {
            writeLog("bufferFileURL is nil.")
            return
        }
        
        // FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        fileDescriptor = open(fileURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        ftruncate(fileDescriptor, off_t(mappedSize))
        
        mappedMemory = mmap(nil, mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, fileDescriptor, 0)
        if mappedMemory == MAP_FAILED {
            NSLog("❌ [EXT] mmap 실패")
        } else {
            NSLog("✅ [EXT] mmap 성공")
        }
    }

    override func broadcastFinished() {
        if mappedMemory != nil && mappedMemory != MAP_FAILED {
            munmap(mappedMemory, mappedSize)
        }
        if fileDescriptor != -1 {
            close(fileDescriptor)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        autoreleasepool {
            guard sampleBufferType == .video else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                writeLog("pixelBuffer 추출 실패")
                return
            }
            guard let mappedMem = mappedMemory, mappedMem != MAP_FAILED else {
                writeLog("mmap 접근 불가")
                return
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            
            // NV12 (YUV420) 포맷 가정
            guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else {
                writeLog("NV12 포맷 오류")
                return
            }
            
            let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
            let ySize = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) * CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            
            let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
            let uvSize = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1) * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            
            let totalSize = ySize + uvSize
            if totalSize > MAX_FRAME_SIZE {
                writeLog("frame size overflow (\(totalSize) bytes)")
                return
            }
            
            // 1. 헤더 (메타데이터) 기록
            let headerPtr = mappedMem.bindMemory(to: SharedFrameBuffer.self, capacity: 1)
            headerPtr.pointee.timeStampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000)
            headerPtr.pointee.width = Int32(CVPixelBufferGetWidth(pixelBuffer))
            headerPtr.pointee.height = Int32(CVPixelBufferGetHeight(pixelBuffer))
            headerPtr.pointee.pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
            headerPtr.pointee.planeCount = 2
            headerPtr.pointee.yPlaneSize = Int32(ySize)
            headerPtr.pointee.uvPlaneSize = Int32(uvSize)
            
            // 2. 실제 프레임 데이터 복사 (헤더 직후 공간에)
            let dataPtr = mappedMem.advanced(by: MemoryLayout<SharedFrameBuffer>.size)
            memcpy(dataPtr, yBase, ySize)
            memcpy(dataPtr.advanced(by: ySize), uvBase, uvSize)
            
            // 3. 소비(메인 앱)를 위해 플래그 설정
            headerPtr.pointee.isReady = true
        }
    }
}
