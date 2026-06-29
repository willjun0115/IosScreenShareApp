//
//  BroadcastPickerView.swift
//  ScreenShareApp
//
//  Created by supercoder on 4/8/26.
//

import SwiftUI
import ReplayKit

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
