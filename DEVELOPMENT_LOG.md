# 프로젝트 개발 로그 (Development Log)

> 프로젝트 개발 과정과 기능 명세를 위한 문서.

---

## 1. 프로젝트 개요 & 목표
* **프로젝트명**: WebRTC iOS 화면 공유 애플리케이션 (`ScreenShareApp`)
* **프로젝트 개요**:
  - WebRTC를 활용하여 iOS 기기의 화면을 실시간으로 전송하는 화면 공유 클라이언트 애플리케이션.
  - 1:N 다중 연결 환경에서 송신자의 리소스 사용량을 최적화하기 위한 기법을 적용 및 검증.
* **개발 목표**:
  - WebRTC 기반 iOS 네이티브 화면 공유 애플리케이션 구축.
  - 비디오 코덱 지원 및 커스텀 프레임 캡처/인코딩 제어 (`KAUEncoderFactory`, `KAUMasterEncoder` 등).
  - WebRTC 성능 데이터 및 디바이스 하드웨어 리소스(CPU, Memory) 실시간 계측/기록 API 구현.
* **핵심 기능**:
  - **화면 캡처 및 전송**: iOS Broadcast Extension 또는 인앱 캡처(In-App Capturer)를 통해 화면 프레임을 획득하고 WebRTC 비디오 트랙으로 전송.
  - **프록시 인코더 구조**: 공유 인코더 및 프록시 인코더 멀티플렉싱을 통한 인코딩 부하 경감.
  - **SDP 협상 모드 제어**: 상호 연결 수립 시 상황에 맞게 송출자 오퍼(Broadcaster as Offerer) 및 수신자 오퍼(Viewer as Offerer) 모드 전환.
  - **키 프레임 생성 제어**: 주기적 I-Frame 강제 생성 제어, 피어 측 키프레임 요청(PLI/FIR) 차단 및 프레임 속도 관리.
  - **macOS 호환 앱**: macOS 타겟과 호환되는 다중 플랫폼 빌드 구현.
  - **자원 성능 텔레메트리**: 주기적으로 WebRTC 연결 지표(RTT, FPS, Bitrate, Loss, Jitter)와 시스템 자원(CPU, Memory) 데이터를 캡처하여 로컬 JSON 파일로 축적.

---

## 2. 개발 환경 & 기술 스택
> 개발 시 사용 중인 라이브러리 및 도구 버전.

* **Target OS**: iOS (Minimum Deployment Target: `iOS 14.0` 이상)
* **Language**: Swift
* **Main SDK / Library**:
  - WebRTC: `WebRTC-SDK` (CocoaPods)
  - signaling: `Socket.IO-Client-Swift`
* **Signaling / Local Test Server**: Node.js / TypeScript (peer_ts)
* **Profiling Tools**: Xcode Instruments, custom telemetry script (`analyze_stats.js`)

---

## 3. 세부 기능 명세 (Detailed Features)

### 1) 화면 캡처 익스텐션 및 프레임 공유 (Screen Capture Extension & Frame Sharing)
* **ReplayKit 기반 시스템 캡처**: iOS의 Broadcast Upload Extension(`ScreenShareExt`)을 구현하여 앱 외부의 모든 iOS 시스템 화면을 백그라운드에서 실시간로 캡처한다.
* **프로세스 간 프레임 공유 (IPC)**: 메인 앱 프로세스와 익스텐션 프로세스 간의 대용량 비디오 프레임 버퍼 전송을 위해 App Group(공유 컨테이너) 메모리 영역을 통한 공유 및 `KAUBroadcastManager`를 이용한 버퍼 동기화 처리를 수행한다.
* **해상도 고정 옵션**: 네트워크 대역폭 하락 시 해상도가 떨어지는 것을 막기 위해 `.maintainResolution` 옵션을 기본 비디오 트랙에 바인딩한다.

### 2) 프록시 인코더 구조 (Proxy Encoder Architecture)
* **KAU 커스텀 인코더 프레임워크**: WebRTC 비디오 엔진의 표준 인코딩 과정을 제어하기 위해 `KAUEncoderFactory`, `KAUProxyEncoder`, `KAUMasterEncoder` 구조를 적용한다.
* **인코딩 부하 중복 방지 (Proxy)**: `KAUProxyEncoder`가 WebRTC 엔진에 등록되는 인터페이스 인터셉터 역할을 수행하며, 실제 물리 H.264 인코더의 스케일링 및 가공 처리는 `KAUMasterEncoder`에 단일 위임하여 여러 피어로 동시에 멀티캐스트 송출 시 발생하는 중복 연산 부하를 차단한다.
* **키 프레임 생성 제어 (Keyframe Control)**: 수신 측의 화면 깨짐을 해소하기 위해 인코더 레벨에서 특정 시간 주기마다 I-Frame 생성을 강제화하는 동기화 메커니즘을 내장하고 있으며, 피어의 무분별한 키프레임 갱신 요청(PLI/FIR)을 선별 차단하여 네트워크 트래픽 급증을 방지한다.

### 3) SDP 모드 제어 (SDP Mode Control)
* **하이브리드 협상 주도권 (`RTCClientMode`)**: 네트워크 토폴로지 및 방화벽 환경에 유연하게 대처하기 위해 송신자와 수신자 중 누가 SDP Offer를 먼저 제안할지 결정하는 협상 모드를 전환할 수 있다.
* **송출자 오퍼 (Broadcaster as Offerer)**: 송출 기기가 화면 스트림의 코덱 및 미디어 명세를 담은 Offer SDP를 생성하여 시그널링 소켓으로 전달하는 구조이다.
* **수신자 오퍼 (Viewer as Offerer)**: 네트워크 방화벽이 강하게 걸려 있는 수신 측(Viewer)이 먼저 Offer SDP를 생성하여 터널을 개방하고, 송출 기기가 이에 응답(Answer SDP)하여 비디오 트랙을 맵핑하는 구조이다.

### 4) 통계 텔레메트리 (Statistics Telemetry)
* **WebRTC QoS 계측**: `WebRTCManager` 내부 타이머를 통해 주기적으로 Peer Connection의 통계 리포트(`RTCStatisticsReport`)를 추출하여 RTT, 지터, 패킷 손실률, 타겟/실제 송출 비트레이트 등의 메트릭을 가공한다.
* **하드웨어 메트릭 수집**: `SystemResourceMonitor` 헬퍼를 통해 iOS Mach OS API의 `task_info` 및 `task_threads`를 질의하여, 앱 프로세스 전체의 CPU 연산량(%)과 물리 메모리(Resident Memory, MB) 점유 상태를 캡처한다.
* **원격 파일 덤프 & 시각화 연동**: 결합된 스냅샷 데이터를 `stats/webrtc_stats_[peerId].json` 파일로 로컬에 기록하고, `analyze_stats.js`를 통해 즉각 반응형 그래프 형태의 HTML 대시보드 리포트로 렌더링한다.

---

## 4. 상세 개발 일지 (Development Journal)
> 새로운 작업, 리팩토링, 기능 구현에 대한 상세 기록

### 📅 2026.07.15
* **진행 작업**:
  - **선호 코덱 선택 UI 및 연동**: iOS 앱 설정 화면(`ContentView.swift`)에서 `H264`, `VP8`, `VP9`, `AV1` 중 선호 코덱을 버튼으로 선택할 수 있도록 UI를 추가하고, 선택된 코덱 파라미터를 `WebRTCManager` -> `KAUEncoderFactory`까지 전파하도록 개선.
  - **소프트웨어 코덱 프록시 우회 처리**: WebRTC iOS SDK의 VP8/VP9 소프트웨어 인코더(C++ 기반 `RTCWrappedNativeVideoEncoder`)는 Swift/ObjC에서 수동으로 `setCallback`을 호출하여 인코딩 루프를 실행할 경우, 원격 비디오 렌더링에 필요한 결과 패킷 콜백을 방출하지 못하는 구조적 제약이 있음. 따라서 `KAUEncoderFactory`에서 H.264 이외의 소프트웨어 코덱에 한해 SDK 기본 소프트웨어 인코더를 직접 리턴하도록 설계를 개선.

### 📅 2026.07.06
* **진행 작업**:
  - **기본 WebRTC 통계 파일 로깅 기능 구현**: SDK의 `RTCStatisticsReport` 객체를 파싱하여 정기적으로 JSON 포맷으로 인코딩한 뒤 앱 Documents 폴더 내에 저장하도록 파일 로깅 연동.
  - **실시간 디바이스 리소스 수집 기능 구현**: 앱 실행 중 Mach 커널 API를 호출하여 실시간 CPU 점유율(%) 및 메모리(Resident Memory, MB) 사용량을 측정하는 `SystemResourceMonitor` 헬퍼 클래스 개발.
  - **WebRTC QoS 통계 연동**: 수집된 CPU/RAM 사용량을 WebRTC 통계(RTT, FPS, Bitrate 등)와 결합하여 주기적으로 `stats/webrtc_stats_*.json`에 파일 기록하도록 연동.
  - **통계 분석 대시보드 스크립트 작성**: 수집된 JSON 로그를 분석하여 Chart.js 기반 반응형 HTML 대시보드 리포트를 자동 빌드하는 `analyze_stats.js` 도구 신규 작성.

### 📅 2026.07.02
* **진행 작업**:
  - **SDP 협상 주도권(Offerer) 설정 기능 개발**: 송출자(Broadcaster)와 수신자(Viewer) 중 누가 먼저 Offer를 생성할지 상황에 따라 동적 전환하기 위해 RTCClientMode 스위치 UI 구현 및 관련 시그널링 통신 최적화.
  - **UI 디자인 및 크로스 플랫폼 최적화**: 송출 시작/중지 버튼 시각적 개선 및 macOS 환경 등 불필요한 OS 타겟에서 방송 시작용 UI 버튼 제거 조치.

### 📅 2026.06.29
* **진행 작업**:
  - **인코더 키프레임 주기 제어**: 수신 측의 초기 디코딩 실패나 유실에 따른 화면 깨짐을 방지하기 위해 `KAUMasterEncoder` 내에서 주기적으로 I-Frame(키프레임) 강제 생성을 제어하는 메커니즘 연동.
  - **고정 해상도 옵션 적용**: 네트워크 상태 저하 시 WebRTC 엔진이 화질 열화 대신 해상도를 고정 유지하도록 `degradationPreference = .maintainResolution` 옵션 기본 적용.
  - **macOS 타겟 화면 캡처 기능 추가**: Mac Catalyst 환경에서 구동될 때 화면을 캡처하기 위한 [ScreenShareApp/KAUMacScreenCapturer.swift](ScreenShareApp/KAUMacScreenCapturer.swift) 클래스 신규 구현 및 [ScreenShareApp/ContentView.swift](ScreenShareApp/ContentView.swift) 내 분기 조건 적용.
  - **프록시 인코더 최적화**: `KAUMasterEncoder`와 `KAUProxyEncoder` 내의 H.264 비디오 프레임 가공 처리 프로세스 안정화 및 [ScreenShareApp/WebRTCManager.swift](ScreenShareApp/WebRTCManager.swift) 연결 흐름 결합 개선.

### 📅 2026.06.18
* **진행 작업**:
  - **WebRTC 라이브러리 판올림**: WebRTC 프레임워크 최신화 및 비디오 인코더/디코더 처리 속도 최적화.
  - **인코더 프록시 및 대역폭 조절 로직 고도화**: `KAUProxyEncoder`와 `KAUMasterEncoder` 내부의 코덱 인풋 스케일링 설정 조정.

### 📅 2026.06.01
* **진행 작업**:
  - **프록시 인코더 핵심 아키텍처 연동**: 커스텀 프레임 인코딩 통제를 위해 [ScreenShareApp/KAUMasterEncoder.swift](ScreenShareApp/KAUMasterEncoder.swift)와 [ScreenShareApp/KAUProxyEncoder.swift](ScreenShareApp/KAUProxyEncoder.swift)의 내부 동작 로직(비디오 프레임 추출, H.264 인코딩 위임 루프)을 본격적으로 완성하고 [ScreenShareApp/WebRTCManager.swift](ScreenShareApp/WebRTCManager.swift) 비디오 소스 트랙에 연결.
  - **카메라 캡처 연동**: 디바이스 카메라를 이용한 `KAUCameraCapturer` 구현 및 이를 표시할 `RemoteVideoView` 연동.

### 📅 2026.05.18 ~ 2026.05.11
* **진행 작업**:
  - **커스텀 인코딩 클래스 프레임워크 초기 설계**: `KAUMasterEncoder.swift`, `KAUProxyEncoder.swift`, `RemoteVideoView.swift`, `KAUCameraCapturer.swift` 파일 구조 설계 및 초기 코드 스탠스 세팅.

### 📅 2026.05.04
* **진행 작업**:
  - **앱-익스텐션 간 화면 버퍼 연동**: ReplayKit 방송 익스텐션과 메인 앱 프로세스 간에 화면 프레임을 공유하기 위한 IPC 공유 컨테이너(`SharedContext.swift`)와 전송 채널 매니저 [ScreenShareApp/KAUBroadcastManager.swift](ScreenShareApp/KAUBroadcastManager.swift), 그리고 프레임 수신기(`KAUFrameReceiver.swift`) 구현.
  - **익스텐션 캡처 고도화**: Broadcast Upload Extension(`ScreenShareExt`) 프로젝트 설정 및 `SampleHandler`를 통해 출력되는 원시 비디오 프레임을 획득하여 WebRTC 트랙에 전달하는 송출 기초 로직 구성.

### 📅 2026.04.21 ~ 2026.04.08
* **진행 작업**:
  - **프로젝트 초기화**: iOS 메인 앱 프로젝트 세팅, Podfile 코코아팟 의존성 라이브러리(`WebRTC-SDK`, `Socket.IO-Client-Swift`) 설정 및 Git 저장소 구성.

---

## 5. 참고 링크 및 문서
* **시그널링 서버 저장소**: [https://github.com/RoadRoot01/WebRTC_v2](https://github.com/RoadRoot01/WebRTC_v2)
* **WebRTC iOS 가이드**: [https://webrtc.org/](https://webrtc.org/)
