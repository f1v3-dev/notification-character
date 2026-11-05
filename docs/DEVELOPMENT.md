# 개발 메모

프로덕션 앱은 Swift와 AppKit/ApplicationServices만 사용합니다. 테스트는 Swift에 포함된 Swift Testing을 사용하며 외부 의존성이 없습니다.

## 표준 환경

Xcode 16 이상을 선택한 상태에서:

```console
swift test --disable-xctest
swift build -c release
swift run --skip-build -c release BundleApp
```

앱 번들은 `dist/Notification Character.app`, 실행 권한을 보존한 압축은 `dist/Notification-Character.zip`에 생성됩니다. CI도 같은 과정을 실행합니다.

## Command Line Tools 6.2 환경

이 환경에서는 Swift Testing 프레임워크 검색 경로가 기본으로 추가되지 않고 Foundation 교차 오버레이 모듈이 누락될 수 있습니다. 다음 옵션으로 확인했습니다. Xcode 전체 설치 환경에는 이 우회 옵션이 필요하지 않습니다.

```console
swift test --disable-xctest \
  -Xswiftc -F \
  -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F \
  -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath \
  -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

빌드 권한이 제한된 에이전트 환경에서는 SwiftPM의 캐시 경로와 Clang 모듈 캐시를 작업 폴더 아래로 지정해야 할 수 있습니다. 앱 실행과는 무관한 빌드 환경 제약입니다.

## 접근성 API

감지 코드는 `DockBadgeReader.swift`에 있습니다. Dock 프로세스의 접근성 트리에서 앱 타일을 찾고, 우선 앱 URL의 bundle identifier로 식별합니다. 이름 매칭은 보조 수단이며 임의의 `WORKS` 부분 문자열로 다른 앱을 잡지 않습니다. 중복 매칭이나 조회 오류를 배지 없음으로 처리하지 않습니다.

- [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue)
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

기존 SwiftBar의 접근성 허용은 새 앱에 적용되지 않으므로 앱을 실행한 다음 사용자가 직접 허용해야 합니다. 자동으로 권한을 부여하거나 우회하지 않습니다. 디버그 CLI의 권한과 `.app` 실행의 권한도 다를 수 있습니다.

## 검증 범위

- Swift Testing 테스트: 세 모드, 읽음/닫기/재감지, 조회 실패 복구, 오래된 값, 적응형 대기 및 화면 경계 243조합, SVG 검증과 파일 보관/복구
- `--smoke-test`: 실제 AppKit 창을 가짜 배지로 표시/숨김, 비활성 창과 클릭 통과 속성, 애니메이션 타이머
- `--inspect-dock`: 현재 실행 환경의 실제 Dock 조회 결과. `permission`이면 해당 실행 주체에 권한이 필요함

실제 메신저의 새 메시지 발생·읽음 전환과 다중 모니터/절전 복귀는 권한 허용 후 실사용 확인이 필요합니다. Dock 배지 자체가 변하지 않는 추가 알림은 이 방식으로 구별할 수 없습니다.

캐릭터 파일 렌더링을 확인하려면 그래픽 세션에서 다음을 실행합니다.

```console
"dist/Notification Character.app/Contents/MacOS/NotificationCharacter" --asset-smoke-test examples/mint-friend.svg
"dist/Notification Character.app/Contents/MacOS/NotificationCharacter" --preview /tmp/character.png --character examples/mint-friend.svg
```

이미지 선택은 `NSOpenPanel`, SVG 렌더링은 AppKit `NSImage`를 사용합니다. WebKit, 셸, 원격 변환 서비스를 사용하지 않습니다. 실제 데이터는 `~/Library/Application Support/NotificationCharacter/Characters/`에 저장되며 Git에 포함되지 않습니다.

GIF는 ImageIO/AppKit 프레임 정보를 사용해 재생하고, 동영상은 AVFoundation의 `AVQueuePlayer`/`AVPlayerLooper`로 반복합니다. 모든 동영상은 무음이며 숨김 시 멈춥니다. 영상 정보는 비동기로 읽어 파일 선택 중 UI가 멈추지 않게 했습니다.

흰 배경 제거는 가장자리와 연결된 밝은 픽셀을 flood fill로 찾습니다. 닫힌 내부의 흰 부분은 유지하고 경계의 흰색 혼합을 줄입니다. 영상은 `AVPlayerItemVideoOutput`으로 프레임을 받아 최대 384px로 처리하고, 숨김 중에는 처리하지 않습니다. 복잡한 배경을 대상으로 하는 인물 분할 모델은 아닙니다.

실제 동영상 재생·배경 제거와 GIF 프레임 전환 확인:

```console
"dist/Notification Character.app/Contents/MacOS/NotificationCharacter" --media-smoke-test /path/to/character.mp4
"dist/Notification Character.app/Contents/MacOS/NotificationCharacter" --preview /tmp/cutout.png --character /path/to/character.mp4 --remove-white-background
```

위 테스트는 임시 폴더에서 생성한 2프레임 GIF의 실제 렌더링 색상 변화와 반복, 동영상의 실제 재생·반복 횟수·무음·투명 프레임·정지를 검사합니다. 사용자 설정은 바꾸지 않습니다.
