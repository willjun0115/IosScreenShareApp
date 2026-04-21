// WebRTCCoreEngine.h
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

/**
 시그널링 메시지를 Swift(SampleHandler)로 전달하기 위한 블록 정의
 @param type 메시지 타입 (예: "answer", "candidate")
 @param targetId 전송 대상 피어 ID
 @param data 전송할 데이터 딕셔너리
 */
typedef void (^SignalingMessageBlock)(NSString *type, NSString *targetId, NSDictionary *data);

@interface WebRTCCoreEngine : NSObject

/// 시그널링 발생 시 호출될 콜백
@property (nonatomic, copy, nullable) SignalingMessageBlock onSignalingMessage;

- (instancetype)init;

/**
 원격 피어로부터 받은 Offer 처리 및 Answer 생성
 */
- (void)handleRemoteOffer:(NSString *)sdp fromPeer:(NSString *)peerId;

/**
 원격 피어로부터 받은 ICE Candidate 처리
 */
- (void)handleRemoteCandidate:(NSDictionary *)data fromPeer:(NSString *)peerId;

/**
 익스텐션의 화면 프레임을 WebRTC 트랙에 주입
 */
- (void)sendVideoBuffer:(CMSampleBufferRef)sampleBuffer;

/**
 특정 피어 연결 종료 및 정리
 */
- (void)removePeer:(NSString *)peerId;

@end

NS_ASSUME_NONNULL_END
