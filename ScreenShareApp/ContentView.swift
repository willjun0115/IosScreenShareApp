//
//  ContentView.swift
//  ScreenShareApp
//

import SwiftUI

struct ContentView: View {
    @AppStorage("broadcastRoomID", store: UserDefaults(suiteName: "group.com.will115.screenshare"))
    var roomID: String = "testRoom"
    
    @StateObject private var broadcastManager = KAUBroadcastManager.shared
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
                    .disabled(broadcastManager.isConnected) // 연결 중엔 수정 불가
            }
            .padding(.horizontal, 30)

            Spacer()
            Button("익스텐션 블랙박스 확인") {
                let defaults = UserDefaults(suiteName: "group.com.will115.screenshare")
                let logs = defaults?.stringArray(forKey: "ExtLogs") ?? ["로그 없음"]
                print("===== 📦 익스텐션 블랙박스 =====")
                for log in logs {
                    print(log)
                }
                print("===============================")
            }
            .foregroundColor(.red)

            if broadcastManager.isConnected {
                VStack(spacing: 15) {
                    Text("서버 연결 완료! 아래 버튼을 눌러 화면을 캡처하세요.")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    
                    // 방송 선택기 뷰 (기존 코드 유지)
                    BroadcastPickerView()
                        .frame(width: 60, height: 60)
                    
                    Button("방송 종료") {
                        broadcastManager.stopConnection()
                    }
                    .foregroundColor(.red)
                    .padding(.top, 10)
                }
                .padding(.bottom, 50)
            } else {
                Button(action: {
                    isInputActive = false
                    broadcastManager.startConnection(roomID: roomID)
                }) {
                    Text("방송 준비 (서버 연결)")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
            }
        }
        .background(
            Color.white
                .onTapGesture {
                    isInputActive = false
                }
        )
    }
}
