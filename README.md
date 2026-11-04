# Notification Character · 알림 고양이

Slack·LINE·NAVER WORKS의 Dock 배지가 생기면 나타나 마우스를 따라오는 **독립 macOS Swift 앱**입니다. 알림 감지, 캐릭터, 메뉴바 배지와 설정을 앱 하나에서 처리합니다.

SwiftBar, 셸 플러그인, AppleScript/JXA, Python, 외부 패키지가 필요하지 않습니다. Dock의 접근성 API를 Swift에서 직접 읽습니다.

## 실행

macOS 13 이상, Swift 6 이상이 필요합니다. Xcode 16 이상을 권장합니다. Command Line Tools만 설치한 환경의 테스트 실행은 [개발 메모](docs/DEVELOPMENT.md)를 참고하세요.

```console
swift test --disable-xctest
swift build -c release
swift run --skip-build -c release BundleApp
open "dist/Notification Character.app"
```

Xcode에서는 `Package.swift`를 열면 됩니다. 배포용 `.app` 번들은 `BundleApp`이 Swift 코드로 조립하고 로컬 서명합니다. 앱을 다른 위치로 옮길 때는 번들 전체를 옮기세요.

첫 실행 후 발바닥 메뉴의 **손쉬운 사용 권한 설정…**에서 이 앱을 허용하세요. 기존 SwiftBar 권한을 물려받지 않습니다. 자동화·화면 기록 권한이나 메신저 계정 토큰은 사용하지 않습니다. 잠금이나 일부 독점 전체화면에서는 캐릭터가 보이지 않을 수 있습니다.

## 알림 표시 방식

발바닥 메뉴에서 선택하며 다음 실행에도 유지됩니다.

| 방식 | 동작 |
| --- | --- |
| 알림을 읽을 때까지 (기본) | 배지가 남아 있는 동안 따라오고, 모두 없어지면 숨습니다. |
| 10초 동안만 | 배지 발생 후 10초 동안 따라옵니다. 추가 배지 증가 시 다시 10초를 셉니다. |
| 직접 닫을 때까지 | 읽어도 유지합니다. **이번 알림 닫기**로 숨습니다. |

**이번 알림 닫기**는 모든 모드에서 사용할 수 있습니다. 같은 배지가 남아 있다는 이유로 다시 나타나지 않으며, 감지 가능한 새 배지가 생기면 다시 나타납니다.

앱별 감지, 0.3–5초 감시 간격, 변화가 없을 때 최대 10초로 늘리기, 메뉴바 점/숫자 표시, 고양이 크기, 따라오기 일시정지, 10초 미리보기도 제공합니다. 기본 메뉴바 표시는 점입니다. 고양이는 클릭을 가로채지 않습니다.

## 감지 범위

macOS 알림 팝업이 아닌 **Dock 배지**가 기준입니다. 배지 없는 알림을 감지할 수 없고, Slack이 계속 `1` 또는 점을 유지하면 그 상태에서 추가로 온 메시지를 구분하지 못합니다. 숫자 배지는 앱이 제공한 값이며 전체 미확인 메시지 수를 보장하지 않습니다. Dock에 앱이 없거나 조회가 실패한 상태를 배지 없음과 구별합니다.

메시지 본문이나 계정 데이터는 읽지 않고 네트워크 통신을 하지 않습니다. 감지는 백그라운드 큐에서 수행하며 API 응답 시간 제한과 적응형 대기를 사용합니다. 절전 복귀 후 다시 감지합니다.

## 코드 구조

- `Sources/NotificationCore/`: 배지 분류, 표시 정책, 감시 간격, 커서 추적 계산
- `Sources/NotificationCharacter/`: AppKit UI와 네이티브 Dock 접근성 감지
- `Sources/BundleApp/`: `.app` 생성·서명용 Swift 도구
- `Tests/NotificationCoreTests/`: 알림 정책, 오류 복구, 배지 및 모니터 좌표 검증
- `.github/workflows/ci.yml`: macOS 테스트·릴리스 빌드·앱 아티팩트

추가 진단 명령:

```console
"dist/Notification Character.app/Contents/MacOS/NotificationCharacter" --inspect-dock
"dist/Notification Character.app/Contents/MacOS/NotificationCharacter" --smoke-test
```

`--smoke-test`는 실제 알림을 보내거나 설정을 바꾸지 않고 가짜 배지로 세 모드의 실제 창 표시/숨김과 클릭 통과 속성을 검증합니다. 그래픽 세션이 필요합니다. `swift test`는 권한이나 그래픽 세션 없이 실행됩니다.

기존 SwiftBar 플러그인을 사용 중이라면 중복 표시를 피하도록 해당 플러그인만 비활성화하세요. 이전 구현은 로컬 `legacy/`에 보관하며 GitHub에는 업로드하지 않습니다.

## 서명과 배포

기본 빌드는 현재 Mac의 CPU 아키텍처용 로컬 ad-hoc 서명입니다. 재빌드 후 접근성 권한을 다시 허용해야 할 수 있습니다. 여러 Mac에 배포하려면 안정적인 Developer ID 서명과 공증을 적용해야 합니다. `BundleApp`은 선택적으로 `CODE_SIGN_IDENTITY` 환경변수를 받아 서명합니다.
