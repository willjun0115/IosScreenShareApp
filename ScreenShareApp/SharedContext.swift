//
//  SharedContext.swift
//  ScreenShareApp
//
//  Created by supercoder on 5/4/26.
//

import Foundation
import CoreVideo

let MAX_FRAME_SIZE = 5_000_000 // 720x1280 NV12 포맷 기준 넉넉한 크기

struct SharedFrameBuffer {
    var isReady: Bool        // 프레임 준비 완료 플래그
    var timeStampNs: Int64   // WebRTC 전송용 타임스탬프
    var width: Int32         // 프레임 너비
    var height: Int32        // 프레임 높이
    var pixelFormat: OSType  // 픽셀 포맷
    var planeCount: Int32    // 평면(Y, UV) 개수
    var yPlaneSize: Int32    // Y 평면 크기
    var uvPlaneSize: Int32   // UV 평면 크기
}

struct SharedContext {
    static let appGroupID = "group.com.will115.screenshare" // 본인의 App Group ID
    static let bufferFileName = "video_buffer.dat"
    
    static var bufferFileURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        return containerURL.appendingPathComponent(bufferFileName)
    }
}
