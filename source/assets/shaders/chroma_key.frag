#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize;
uniform vec3 uKey;
uniform float uSimilarity;
uniform float uBlend;
uniform sampler2D uTexture;
out vec4 fragColor;

// Limited-range BT.601 chroma, matching FFmpeg's RGB key conversion.
vec2 chroma(vec3 rgb) {
  return vec2(dot(rgb, vec3(-0.148, -0.291, 0.439)),
              dot(rgb, vec3(0.439, -0.368, -0.071)));
}
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 pixel = texture(uTexture, uv);
  float distanceSum = 0.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec4 samplePixel = texture(uTexture, clamp(uv + vec2(x, y) / uSize, vec2(0.0), vec2(1.0)));
      vec3 rgb = samplePixel.rgb / max(samplePixel.a, 0.00001);
      distanceSum += length(chroma(rgb) - chroma(uKey)) / sqrt(2.0);
    }
  }
  float difference = distanceSum / 9.0;
  float alpha = uBlend > 0.0001 ? clamp((difference - uSimilarity) / uBlend, 0.0, 1.0) : step(uSimilarity + 0.000001, difference);
  fragColor = pixel * alpha;
}
