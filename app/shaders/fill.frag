#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;      // 이 셰이더가 채우는 사각형의 크기 (캔버스 논리 단위)
uniform vec2 uMapSize;   // 인덱스맵 크기 (픽셀)
uniform sampler2D uRegions;
uniform sampler2D uPalette;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // 텍셀 중심으로 스냅한다. 샘플러가 선형 보간이어도 정확히 그 텍셀 값이
  // 나오므로 필터 모드와 무관하게 영역 ID 가 섞이지 않는다. 측정해 보면
  // 지금 Flutter 는 nearest 지만, 백엔드나 버전에 따라 달라질 수 있고
  // 어긋나면 조용히 엉뚱한 칸이 칠해진다.
  vec2 snapped = (floor(uv * uMapSize) + 0.5) / uMapSize;
  vec4 r = texture(uRegions, snapped);

  float lo = floor(r.r * 255.0 + 0.5);
  float hi = floor(r.g * 255.0 + 0.5);
  float id = lo + hi * 256.0;

  // 0 = 선, 1 = 배경. 둘 다 채움 레이어에서는 투명하다.
  if (id < 2.0) {
    fragColor = vec4(0.0);
    return;
  }

  // 팔레트는 256x256. ID n 은 (n%256, n/256) 에 놓이므로 lo, hi 가 곧 좌표다.
  vec4 c = texture(uPalette, (vec2(lo, hi) + 0.5) / 256.0);

  // Flutter 셰이더 출력은 미리 곱해진 알파다.
  fragColor = vec4(c.rgb * c.a, c.a);
}
