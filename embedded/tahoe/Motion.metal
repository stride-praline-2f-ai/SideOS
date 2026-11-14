#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Original inverse strip mapping, informed by the community Genie experiments.
// An approximation, not Apple's WindowServer implementation. Signed destination
// motion supports targets on either side or above/below the source window.
[[ stitchable ]] half4 tahoeGenie(float2 position, SwiftUI::Layer layer,
                                 float4 source, float4 target, float progress) {
    float p = clamp(progress, 0.0f, 1.0f);
    float top = mix(source.y, target.y, p);
    float height = max(1.0f, mix(source.w, target.w, p));
    float v = (position.y - top) / height;
    if (v < 0.0f || v > 1.0f) return half4(0);
    float direction = target.y >= source.y ? v : 1.0f - v;
    float bend = clamp(p + p * (1.0f - p) * (direction * 1.6f - 0.8f), 0.0f, 1.0f);
    float width = max(1.0f, mix(source.z, target.z, bend));
    float center = mix(source.x + source.z * 0.5f, target.x + target.z * 0.5f, bend);
    float u = (position.x - center) / width + 0.5f;
    if (u < 0.0f || u > 1.0f) return half4(0);
    return layer.sample(source.xy + float2(u * source.z, v * source.w));
}
