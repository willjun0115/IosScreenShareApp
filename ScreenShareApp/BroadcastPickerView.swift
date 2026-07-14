//
//  BroadcastPickerView.swift
//  ScreenShareApp
//

import SwiftUI
import ReplayKit

// 방송 시작 버튼 클릭 시 뜨는 팝업 뷰(iOS 전용)
#if os(iOS)
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        
        picker.preferredExtension = "com.will115.ScreenShareApp.ScreenShareExt"
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
#endif
