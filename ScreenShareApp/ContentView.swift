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
    
    // 현재 선택된 공유 모드를 추적하는 상태 변수
    @State private var currentSource: captureSource? = nil
    
    // SDP 협상 구조(Mode)를 선택하는 상태 변수
    @State private var clientMode: RTCClientMode = .broadcasterAsOfferer

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 10) {
                Text("스트리밍 공유")
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
                
                Text("협상 모드 (SDP)")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                
                HStack(spacing: 0) {
                    ForEach(RTCClientMode.allCases) { mode in
                        Button(action: {
                            clientMode = mode
                        }) {
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .foregroundColor(clientMode == mode ? .white : .primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(clientMode == mode ? Color.blue : Color(UIColor.systemGray5))
                        }
                        .disabled(broadcastManager.isConnected)
                    }
                }
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                )
            }
            .padding(.horizontal, 30)

            Spacer()
            
            // 디버깅용 블랙박스 버튼 (유지)
//            Button("익스텐션 블랙박스 확인") {
//                let defaults = UserDefaults(suiteName: "group.com.will115.screenshare")
//                let logs = defaults?.stringArray(forKey: "ExtLogs") ?? ["로그 없음"]
//                print("===== 📦 익스텐션 블랙박스 =====")
//                for log in logs {
//                    print(log)
//                }
//                print("===============================")
//            }
//            .foregroundColor(.red)

            if broadcastManager.isConnected {
                VStack(spacing: 20) {
                    // 원격 비디오 트랙이 존재하면 화면에 출력
                    if let remoteTrack = broadcastManager.remoteVideoTrack {
                        Text("방송 수신 중")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        RemoteVideoView(videoTrack: remoteTrack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 300) // 화면 비율에 맞게 높이 조절
                            .background(Color.black)
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                    } else if currentSource == .screen {
                        Text("서버 연결 완료!\n아래 버튼을 눌러 화면 캡처를 시작하세요.")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.center)
                        
                        #if targetEnvironment(macCatalyst)
                        Text("macOS 화면 캡처가 진행 중입니다.")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .padding()
                        #elseif os(iOS)
                        if ProcessInfo.processInfo.isiOSAppOnMac {
                            Text("macOS 화면 캡처가 진행 중입니다.")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .padding()
                        } else {
                            BroadcastPickerView()
                                .frame(width: 60, height: 60)
                        }
                        #else
                        Text("macOS 화면 캡처가 진행 중입니다.")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .padding()
                        #endif
                    } else if currentSource == .camera {
                        Text("📷 전면 카메라 공유 중입니다...")
                            .font(.headline)
                            .foregroundColor(.green)
                    } else {
                        // ✨ 추가: 방장도 아니고 시청 트랙도 못 받은 상태 (연결 대기)
                        Text("방송 서버 연결됨. 역할을 대기 중입니다...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Button("방송 종료") {
                        broadcastManager.stopConnection()
                        currentSource = nil // 상태 초기화
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
                    .padding(.horizontal, 30)
                }
                .padding(.bottom, 50)
            } else {
                VStack(spacing: 15) {
                    Button(action: {
                        isInputActive = false
                        currentSource = .screen
                        broadcastManager.startStreaming(source: .screen, roomID: roomID, mode: clientMode)
                    }) {
                        Text("화면 공유 시작")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        isInputActive = false
                        currentSource = .camera
                        broadcastManager.startStreaming(source: .camera, roomID: roomID, mode: clientMode)
                    }) {
                        Text("카메라 공유 시작")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        isInputActive = false
                        currentSource = nil // 시청자는 로컬 캡처 소스가 없음을 명시
                        // 캡처 파이프라인을 건너뛰고 서버 연결(Socket)만 시작합니다.
                        broadcastManager.startConnection(roomID: roomID, mode: clientMode)
                    }) {
                        Text("방송 시청하기")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
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
