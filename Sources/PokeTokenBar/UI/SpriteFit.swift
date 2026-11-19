import CoreGraphics

/// 스프라이트를 정사각 프레임에 넣을 때의 **비율 유지** 기하 — 팝오버(SpriteView)와 메뉴바가 공유한다.
///
/// Gen-V 움직이는 스프라이트(GIF)는 캔버스가 종마다 다르고 정사각이 아니다 — 잭키(#325) 36×66,
/// 피카츄(#25) 50×46, 팬텀(#143) 74×75. 반면 정적 스프라이트는 96×96, 아이템은 30×30 으로 전부
/// 정사각이라 "size×size 로 늘려 채우기"가 정적 경로에서는 아무 증상이 없다가 GIF 경로에서만
/// 왜곡으로 드러났다(잭키 = 가로 1.83배). 두 호출부가 같은 식을 쓰게 여기로 모은다.
enum SpriteFit {
    /// `box`×`box` 정사각 안에 원본 비율을 유지해 맞춘 크기(contentMode .fit — 긴 변이 box 에 닿는다).
    /// 원본 크기가 비었으면(디코드 실패 등) 정사각 폴백 — 0 나눗셈 방지.
    static func size(for pixelSize: CGSize, box: CGFloat) -> CGSize {
        size(for: pixelSize, width: box, height: box)
    }

    /// Same fit inside a `width`×`height` box. An empty source falls back to a square on the shorter side.
    static func size(for pixelSize: CGSize, width: CGFloat, height: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            let side = min(width, height)
            return CGSize(width: side, height: side)
        }
        let scale = min(width / pixelSize.width, height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }
}
