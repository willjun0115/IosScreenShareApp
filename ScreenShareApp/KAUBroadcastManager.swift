//
//  KAUBroadcastManager.swift
//  ScreenShareApp
//
//  Created by supercoder on 5/4/26.
//

import Foundation
import WebRTC
import SocketIO

class KAUBroadcastManager: ObservableObject {
    static let shared = KAUBroadcastManager()
    
    var socketManager: SocketManager?
    var socket: SocketIOClient?
    var rtcManager: WebRTCManager?
    
    @Published var isConnected = false
    
    func startConnection(roomID: String) {
        let serverURL = URL(string: "https://192.168.219.103:8000")!
        socketManager = SocketManager(socketURL: serverURL, config: [
            .log(false),
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectWait(1),
            .secure(true)
        ])
        socket = socketManager?.defaultSocket
        
        rtcManager = WebRTCManager(socket: socket!)
        
        KAUReceiver.shared.startReceiving(rtcManager: rtcManager!)
        BackgroundAudioPlayer.shared.start()
        
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            NSLog("✅ 서버 연결 성공 (Room: \(roomID))")
            
            self?.socket?.emit("join", ["room": roomID, "type": "broadcast"])
            
            DispatchQueue.main.async {
                self?.isConnected = true
            }

            self?.socket?.on("my-id") { data, _ in
                if let id = data[0] as? String {
                    self?.rtcManager?.myId = id
                }
            }

            self?.socket?.on("root-broadcaster") { _, _ in
                NSLog("✅ Root 방송자로 지정됨. 시청자의 Offer를 대기합니다.")
            }

            self?.socket?.on("offer") { [weak self] data, _ in
                if let dict = data[0] as? [String: Any],
                   let fromId = dict["from"] as? String,
                   let sdpData = dict["data"] as? [String: Any],
                   let sdpString = sdpData["sdp"] as? String {
                    self?.rtcManager?.handleOffer(from: fromId, sdp: sdpString)
                }
            }
            
            self?.socket?.on("candidate") { [weak self] data, _ in
                if let dict = data[0] as? [String: Any],
                   let fromId = dict["from"] as? String,
                   let candData = dict["data"] as? [String: Any],
                   let candidateDict = candData["candidate"] as? [String: Any] {
                    self?.rtcManager?.handleCandidate(from: fromId, candidateDict: candidateDict)
                }
            }
        }
        
        socket?.connect()
    }
    
    func stopConnection() {
        KAUReceiver.shared.stopReceiving() // frame receiver 종료
        BackgroundAudioPlayer.shared.stop() // background audio 종료
        socket?.disconnect()
        socketManager = nil
        rtcManager = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
