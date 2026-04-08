#version 460 core
#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture;
uniform float uSeed;
uniform float uIntensity;
uniform vec4 uSrcRect; 
uniform vec2 uAtlasSize;
uniform float uRotate;

out vec4 fragColor;

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec2 getUV(vec2 localCoord) {
    vec2 clampedCoord = clamp(localCoord, vec2(0.0), uSrcRect.zw - vec2(1.0));
    vec2 pos;
    if (uRotate > 0.5) {
        pos.x = uSrcRect.x + clampedCoord.y;
        pos.y = uSrcRect.y + (uSrcRect.w - clampedCoord.x);
    } else {
        pos = uSrcRect.xy + clampedCoord;
    }
    return pos / uAtlasSize;
}

void main() {
    vec2 localCoord = FlutterFragCoord().xy;
    
    // Row shift glitch
    float row = floor(localCoord.y / 2.0);
    float shift = 0.0;
    if (rand(vec2(row, uSeed)) < uIntensity * 0.3) {
        shift = (rand(vec2(row, uSeed + 1.0)) - 0.5) * 10.0 * uIntensity;
    }
    
    vec2 shiftedCoord = localCoord + vec2(shift, 0.0);
    
    vec4 color = texture(uTexture, getUV(shiftedCoord));
    
    // RGB split
    float split = uIntensity * 3.0;
    float r = texture(uTexture, getUV(shiftedCoord + vec2(split, 0.0))).r;
    float b = texture(uTexture, getUV(shiftedCoord - vec2(split, 0.0))).b;
    
    // Add some noise
    float noise = (rand(localCoord + vec2(uSeed)) - 0.5) * 0.1 * uIntensity;
    
    fragColor = vec4(vec3(r, color.g, b) + noise, color.a);
}
