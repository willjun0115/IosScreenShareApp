//
//  ContentView.swift
//  ScreenShareApp
//
//  Created by supercoder on 4/8/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("broadcastRoomID", store: UserDefaults(suiteName: "group.com.will115.screenshare"))
    var roomID: String = "testRoom"
//    @AppStorage("temp", store: UserDefaults(suiteName: "group.com.will115.screenshare"))
//    var temp: Int = 100
    
    @FocusState private var isInputActive: Bool

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 10) {
                Text("화면 공유")
                    .font(.largeTitle)
                    .bold()
            }
            .padding(.top, 50)

            VStack(alignment: .leading, spacing: 8) {
                Text("Room ID")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                TextField("방 번호를 입력하세요", text: $roomID)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($isInputActive)
            }
            .padding(.horizontal, 30)

            Spacer()

            VStack(spacing: 15) {
                Text("아래 버튼을 눌러 방송을 시작하세요")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                // 방송 선택기 뷰
                BroadcastPickerView()
                    .frame(width: 60, height: 60)
            }
            .padding(.bottom, 50)
        }
        .background(
            Color.white
                .onTapGesture {
                    isInputActive = false
                }
        )
    }
}

#Preview {
    ContentView()
}
