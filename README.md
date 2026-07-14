# iOS & macOS WebRTC Screen Share Application

WebRTC 프로토콜을 활용하여 iOS 및 macOS(Mac Catalyst) 환경에서 실시간으로 화면 및 카메라 스트림을 공유하고 시청할 수 있는 클라이언트 애플리케이션입니다.

1:N 다중 연결 송출 환경에서 CPU/메모리 자원 소모를 최소화하기 위한 **공유 인코더 프레임워크**와 상황별 연결 대응을 위한 **SDP 하이브리드 협상 제어**, 그리고 실시간 **성능 & 디바이스 자원 텔레메트리** 기능이 탑재되어 있습니다.

---

## 시스템 요구사양

- **개발 언어**: Swift (iOS / Mac Catalyst)
- **개발 도구**: Xcode 14.0 이상, CocoaPods
- **OS 요구사양**:
  - iOS 기기: iOS 14.0 이상
  - macOS 기기: macOS 12.3 이상
- **주요 외부 라이브러리**:
  - WebRTC: `WebRTC-SDK`
  - Signaling: `Socket.IO-Client-Swift`
- **시그널링 서버**: Node.js 기반 서버

---

## 프로젝트 폴더 구조

```text
IosScreenShareApp/
├── ScreenShareApp/               # 메인 앱 프로젝트 소스
│   ├── ContentView.swift         # 메인 SwiftUI 인터페이스
│   ├── KAUBroadcastManager.swift # 소켓 시그널링 통신 및 미디어 파이프라인 조율
│   ├── WebRTCManager.swift       # RTCPeerConnection 생성, SDP/ICE 조율 및 리소스 모니터 엔진
│   ├── KAUMasterEncoder.swift    # 실제(마스터) 인코더 관리 및 프레임 분배 Multiplexer
│   ├── KAUProxyEncoder.swift     # WebRTC 비디오 엔진에 등록되는 가상(프록시) 인코더
│   ├── KAUFrameReceiver.swift    # App Group 공유 메모리(mmap) 수신 및 WebRTC 바인딩 폴링 루프
│   ├── KAUMacScreenCapturer.swift# macOS 용 ScreenCaptureKit 기반 캡처 모듈
│   ├── BackgroundAudioPlayer.swift# 백그라운드 생존을 위한 무음 오디오 재생 모듈
│   └── SharedContext.swift       # 프로세스 간 공유 메모리 파일 및 구조체 정의
│
├── ScreenShareExt/               # ReplayKit Broadcast Upload Extension 소스
│   └── SampleHandler.swift       # ReplayKit 비디오 프레임을 획득하여 공유 파일 메모리에 기록
│
├── Podfile                       # CocoaPods 의존성 설정 파일
├── analyze_stats.js              # QoS & 자원 계측 JSON 분석 및 시각화 리포트 생성 스크립트
├── DEVELOPMENT_LOG.md            # 단계별 상세 개발 내용 및 히스토리 로그
└── README.md                     # 본 프로젝트 매뉴얼 문서
```

---

## 실행 방법

### 1. 시그널링 서버 구동
본 클라이언트와 연동할 시그널링 서버(`peer_ts`) 저장소에서 의존성을 빌드하고 먼저 실행합니다.
```bash
# peer_ts 프로젝트 루트
npm install
npm start
```

### 2. 클라이언트 프로젝트 의존성 설치
`IosScreenShareApp` 루트 디렉토리에서 CocoaPods을 이용하여 라이브러리를 내려받습니다.
```bash
# IosScreenShareApp 루트
pod install
```
설치가 완료되면 Xcode에서 `ScreenShareApp.xcworkspace` 파일을 엽니다.

### 3. Xcode 설정 및 빌드
iOS 기기에서 전체 화면 공유(Broadcast Extension)가 작동하려면 **App Group** 및 **Apple Developer 계정 프로비저닝** 설정이 필요합니다.

1. **App Group 생성 및 매핑**:
   - Xcode의 `Signing & Capabilities` 탭으로 이동합니다.
   - `ScreenShareApp` 타겟과 `ScreenShareExt` 타겟 모두 동일한 App Group 식별자(예: `group.com.will115.screenshare`)를 추가 및 활성화합니다.
   - 해당 App Group ID는 [SharedContext.swift](ScreenShareApp/SharedContext.swift) 파일의 `appGroupID` 변수값과 일치해야 합니다.
2. **App ID / Bundle Identifier 확인**:
   - 고유한 Bundle ID를 사용하고 해당 인증서 세팅을 확인합니다.
3. 빌드 타겟을 선택한 뒤 **Run (Cmd + R)**을 실행합니다.

---

## 성능 리포트 분석 도구 활용

수집된 자원 및 성능 덤프 JSON 파일을 통해 분석 리포트 그래프(HTML)를 그리는 방법입니다.

1. **통계 로그 확인**:
   - 앱 내에서 화면 공유나 방송 시청이 활성화되면 실시간 통계가 수집되며, 테스트 세션 종료 시점에 앱 디렉토리 내에 `webrtc_stats_[peerId].json` 형식으로 파일이 저장됩니다.
2. **대시보드 생성**:
   - 프로젝트 루트 디렉토리에서 아래 명령어로 스크립트를 실행합니다. (Node.js 환경 필요)
   ```bash
   node analyze_stats.js [통계_JSON_파일_경로]
   ```
3. **결과 시각화**:
   - 명령어가 수행되면 같은 경로에 `[통계_JSON_파일명]_report.html` 파일이 생성됩니다.
   - 이 파일을 웹 브라우저(Chrome 등)로 열면 **비트레이트, 지연 시간(RTT), 프레임레이트(FPS), 패킷 손실률, 그리고 디바이스 CPU/메모리 점유율**이 동기화된 고성능 시각화 차트로 출력됩니다.
