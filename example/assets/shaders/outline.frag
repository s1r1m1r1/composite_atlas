#version 460 core
#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture;
uniform float uThickness;
uniform vec4 uColor;
uniform vec4 uSrcRect; 
uniform vec2 uAtlasSize;
uniform float uRotate;
// [top, left, right, bottom]
uniform vec4 uPadding; 
// 1.0 to only draw the outline, 0.0 to draw sprite + outline
uniform float uOutlineOnly; 

out vec4 fragColor;

vec2 getUV(vec2 localCoord) {
    // Clamp coordinates to avoid sampling adjacent sprites in the atlas
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
    // Current coord in the PADDED layer
    vec2 layerCoord = FlutterFragCoord().xy;
    // Coord in the ORIGINAL sprite space
    vec2 spriteCoord = layerCoord - vec2(uPadding.y, uPadding.x);
    
    // Check if we are outside the valid sampling range (including outline)
    // We allow sampling uThickness pixels outside the sprite bounds
    if (spriteCoord.x < -uThickness || spriteCoord.y < -uThickness || 
        spriteCoord.x > uSrcRect.z + uThickness || spriteCoord.y > uSrcRect.w + uThickness) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 centerColor = texture(uTexture, getUV(spriteCoord));
    
    if (centerColor.a > 0.2) {
        if (uOutlineOnly > 0.5) {
            fragColor = vec4(0.0);
        } else {
            fragColor = centerColor;
        }
    } else {
        float neighborAlpha = 0.0;
        // Sample neighbors to check for outline
        // SkSL requirement: loop bounds must be constant. 
        // We use a fixed range and skip based on uThickness.
        const float MAX_THICK = 5.0; 
        for (float x = -MAX_THICK; x <= MAX_THICK; x += 1.0) {
            if (abs(x) > uThickness) continue;
            for (float y = -MAX_THICK; y <= MAX_THICK; y += 1.0) {
                if (abs(y) > uThickness) continue;
                
                if (x == 0.0 && y == 0.0) continue;
                // Optimization: circular outline
                if (x*x + y*y > uThickness*uThickness + 0.5) continue;
                
                vec2 sampleCoord = spriteCoord + vec2(x, y);
                // Only sample if within the sprite bounds to avoid leakage
                if (sampleCoord.x >= 0.0 && sampleCoord.y >= 0.0 && 
                    sampleCoord.x < uSrcRect.z && sampleCoord.y < uSrcRect.w) {
                    neighborAlpha = max(neighborAlpha, texture(uTexture, getUV(sampleCoord)).a);
                }
            }
        }
        
        if (neighborAlpha > 0.2) {
            fragColor = uColor;
        } else {
            fragColor = vec4(0.0);
        }
    }
}
