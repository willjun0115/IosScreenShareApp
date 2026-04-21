// WebRTCCoreEngine.mm
#import "WebRTCCoreEngine.h"
#import <WebRTC/WebRTC.h>
#import <WebRTC/RTCAudioSession.h>

// WebRTC C++ Core Headers
#include <map>
#include <string>

@interface WebRTCCoreEngine() <RTCPeerConnectionDelegate> {
    RTCPeerConnectionFactory *_factory;
    RTCVideoSource *_videoSource;
    RTCVideoTrack *_videoTrack;
    RTCVideoCapturer *_videoCapturer;
    
    // C++ std::map을 사용하여 피어별로 RTCPeerConnection 인스턴스를 관리
    // Swift 딕셔너리보다 오버헤드가 적고 로우레벨 제어가 용이함
    std::map<std::string, RTCPeerConnection*> _peerConnections;
}
@end

@implementation WebRTCCoreEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupNativeWebRTC];
    }
    return self;
}

- (void)setupNativeWebRTC {
    // 1. 런타임 해킹을 통한 RTCAudioSession 강제 제어 (헤더 불필요)
    Class audioSessionClass = NSClassFromString(@"RTCAudioSession");
    if (audioSessionClass) {
        // sharedSession 가져오기
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id audioSession = [audioSessionClass performSelector:NSSelectorFromString(@"sharedInstance")];
        
        // Configuration 잠금
        [audioSession performSelector:NSSelectorFromString(@"lockForConfiguration")];
        
        // KVC를 사용하여 primitive BOOL 값 강제 주입
        [audioSession setValue:@(YES) forKey:@"useManualAudio"];
        [audioSession setValue:@(NO) forKey:@"isAudioEnabled"];
        
        // Configuration 잠금 해제
        [audioSession performSelector:NSSelectorFromString(@"unlockForConfiguration")];
        #pragma clang diagnostic pop
        
        NSLog(@"[CoreEngine] 런타임 해킹으로 WebRTC 오디오 강제 차단 완료");
    } else {
        NSLog(@"[CoreEngine] ⚠️ RTCAudioSession 클래스를 찾을 수 없습니다.");
    }
    
    // 2. 비디오 인코더 설정 및 팩토리 생성
    RTCDefaultVideoEncoderFactory *encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
    RTCDefaultVideoDecoderFactory *decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
    
    _factory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory decoderFactory:decoderFactory];
                
    _videoSource = [_factory videoSource];
    _videoTrack = [_factory videoTrackWithSource:_videoSource trackId:@"video0"];
    _videoCapturer = [[RTCVideoCapturer alloc] initWithDelegate:_videoSource];
    
    NSLog(@"[CoreEngine] 비디오 전용 WebRTC Factory 초기화 완료");
}

- (void)handleRemoteOffer:(NSString *)sdp fromPeer:(NSString *)peerId {
    std::string pId = [peerId UTF8String];
    
    // 연결이 없으면 새로 생성
    if (_peerConnections.find(pId) == _peerConnections.end()) {
        RTCConfiguration *config = [[RTCConfiguration alloc] init];
        config.iceServers = @[[[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun.l.google.com:19302"]]];
        
        RTCPeerConnection *pc = [_factory peerConnectionWithConfiguration:config constraints:[[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil] delegate:self];
        
        // 단일 비디오 트랙을 공유 (Fan-out)
        [pc addTrack:_videoTrack streamIds:@[@"stream0"]];
        _peerConnections[pId] = pc;
    }
    
    RTCPeerConnection *pc = _peerConnections[pId];
    RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:RTCSdpTypeOffer sdp:sdp];
    
    // ⭐️ 1. 블록 밖에서 약한 참조(weak) 선언 (순환 참조 고리 끊기)
    __weak typeof(pc) weakPc = pc;
    __weak typeof(self) weakSelf = self;
    
    [pc setRemoteDescription:remoteSdp completionHandler:^(NSError * _Nullable error) {
        // ⭐️ 2. 블록 안에서 강한 참조(strong)로 변환하여 실행 도중 객체가 사라지는 것 방지
        __strong typeof(weakPc) strongPc = weakPc;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        
        // 만약 이미 메모리에서 해제되었다면 안전하게 종료
        if (error || !strongPc || !strongSelf) return;
        
        [strongPc answerForConstraints:[[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil] completionHandler:^(RTCSessionDescription * _Nullable answer, NSError * _Nullable error) {
            
            if (error) return;
            
            [strongPc setLocalDescription:answer completionHandler:^(NSError * _Nullable error) {
                // 블록 안에서는 반드시 strongSelf를 사용하여 접근
                if (strongSelf.onSignalingMessage) {
                    strongSelf.onSignalingMessage(@"answer", peerId, @{@"type": @"answer", @"sdp": answer.sdp});
                }
            }];
        }];
    }];
}

- (void)handleRemoteCandidate:(NSDictionary *)data fromPeer:(NSString *)peerId {
    std::string pId = [peerId UTF8String];
    if (_peerConnections.find(pId) != _peerConnections.end()) {
        RTCIceCandidate *candidate = [[RTCIceCandidate alloc]
                                      initWithSdp:data[@"candidate"]
                                      sdpMLineIndex:[data[@"sdpMLineIndex"] intValue]
                                      sdpMid:data[@"sdpMid"]];
        [_peerConnections[pId] addIceCandidate:candidate];
    }
}

- (void)sendVideoBuffer:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;
    
    // [최적화] Zero-copy에 가까운 픽셀 버퍼 래핑
    RTCCVPixelBuffer *rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
    int64_t timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000000000;
    
    RTCVideoFrame *videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer rotation:RTCVideoRotation_0 timeStampNs:timeStampNs];
    
    // 모든 피어가 공유하는 단일 Source에 주입하여 인코딩 부하 분산
    [_videoSource capturer:_videoCapturer didCaptureVideoFrame:videoFrame];
}

- (void)removePeer:(NSString *)peerId {
    std::string pId = [peerId UTF8String];
    if (_peerConnections.find(pId) != _peerConnections.end()) {
        _peerConnections[pId].delegate = nil;
        [_peerConnections[pId] close];
        _peerConnections.erase(pId);
    }
}

#pragma mark - RTCPeerConnectionDelegate

- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate {
    // 역탐색하여 해당 피어 ID 찾기
    for (auto const& [pId, pc] : _peerConnections) {
        if (pc == peerConnection) {
            NSString *targetId = [NSString stringWithUTF8String:pId.c_str()];
            NSDictionary *data = @{
                @"sdpMLineIndex": @(candidate.sdpMLineIndex),
                @"sdpMid": candidate.sdpMid,
                @"candidate": candidate.sdp
            };
            if (self.onSignalingMessage) self.onSignalingMessage(@"candidate", targetId, data);
            break;
        }
    }
}

// 나머지 필수 델리게이트는 빈 메서드로 구현 (컴파일 에러 방지)
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)state {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream {}
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)state {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)state {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates {}
- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {}

@end
