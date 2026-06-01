# Deplite SDK (Swift)

[Deplite](https://deplite.io)를 Swift에서 호출하는 공식 SDK 입니다.<br/>
iOS·macOS 앱과 서버사이드 Swift 어디서나 동작합니다.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Deplite/sdk-ios.git", from: "0.1.0"),
]
```

Xcode에서는 File → Add Package Dependencies… 메뉴로 같은 URL을 추가하시면 됩니다.

최소 플랫폼: iOS 15, macOS 12, tvOS 15, watchOS 8, visionOS 1.

## 어떤 모드를 써야 할까

| | External | Embedded |
| --- | --- | --- |
| 언제 쓰나 | 내 앱·CI·서버에서 Deplite를 **호출**할 때 | 내 앱·기기가 Deplite의 **작업 노드**가 될 때 |
| 인증 | API 토큰 | 1회용 설치 코드로 등록 후 Ed25519 서명 |
| 대표 예 | 트리거 발사, 파일 업로드/다운로드 | 키오스크, 무인 단말기, 디바이스 자동화 |

## 빠른 시작 (External)

```swift
let deplite = Deplite(apiToken: "dep_xxxxx")

let job = try await deplite.triggers.run(
    triggerId: "00000000-0000-0000-0000-000000000000",
    params: ["ref": "main"]
)

let uploaded = try await deplite.files.upload(fileURL: URL(fileURLWithPath: "/tmp/build.ipa"))
```

모든 함수는 `async`라서 `async` 컨텍스트에서 호출해주세요.

---

더 자세한 내용은 [Deplite 가이드](https://docs.deplite.io/guide)를 참고해주세요.

## 라이선스

[Apache-2.0. LICENSE](LICENSE)
