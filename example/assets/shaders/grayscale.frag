#version 460 core
// v2: Added uSrcRect and uAtlasSize support

#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture;
uniform float uIntensity;
// [left, top, width, height] of the sprite in the source atlas (in pixels)
uniform vec4 uSrcRect; 
// Total [width, height] of the source atlas (in pixels)
uniform vec2 uAtlasSize;
// 0.0 or 1.0 depending on rotation
uniform float uRotate;

out vec4 fragColor;

void main() {
    // Local coordinates within the sprite being drawn (0..width, 0..height)
    vec2 localCoord = FlutterFragCoord().xy;
    
    vec2 pos;
    if (uRotate > 0.5) {
        // Sprite is rotated 90 deg CCW in the atlas.
        // x_local maps to y_atlas (top-to-bottom)
        // y_local maps to x_atlas (right-to-left) 
        // No, let's use the standard mapping:
        pos.x = uSrcRect.x + localCoord.y;
        pos.y = uSrcRect.y + (uSrcRect.w - localCoord.x);
    } else {
        pos = uSrcRect.xy + localCoord;
    }
    
    // Normalize for texture sampling (0..1)
    vec2 uv = pos / uAtlasSize;
    
    vec4 color = texture(uTexture, uv);
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    
    fragColor = mix(color, vec4(vec3(gray), color.a), uIntensity);
}
