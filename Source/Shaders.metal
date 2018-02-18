#include <metal_stdlib>
#import "Shader.h"

using namespace metal;

float2 cMul(float a, float2 b) { return float2(a * b.x - a * b.y, a * b.y + a * b.x); }
float2 cMul(float2 a, float2 b) { return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
float2 cSqr(float2 a) { return cMul(a, a); }
float4 cMul(float4 a, float4 b) { return float4(cMul(a.xy, b.xy), cMul(a.xy, b.zw) + cMul(a.zw, b.xy)); }
float4 cSqr(float4 a) { return cMul(a, a); }

kernel void inflectionShader
(
    texture2d<float, access::write> outTexture [[texture(0)]],
    constant Control &control [[buffer(0)]],
    constant float3 *inflection [[buffer(1)]],
    uint2 p [[thread_position_in_grid]])
{
    float2 pos = control.sCenter + float2(p.x,p.y) * control.zoom;
    float4 c = float4(pos, 1, 0.0);
    
    if (control.inflectionCount > 0) {
        float r = inflection[0].z;
        float4 f = float4(inflection[0].xy, 0.0, 0.0);

        float4 d = c;
        if(!control.centering) d -= f;
        
        c = cSqr(d / r) * r + f;
    }
    
    for(int i = 1; i < control.inflectionCount; ++i)  {
        float r = inflection[i].z;
        float4 f = float4(inflection[i].xy, 0.0, 0.0);
        float4 d = c - f;
        c = cSqr(d / r) * r + f;
    }
    
    float4 z = float4(0,0,0,0);
    
    if(control.julia && control.inflectionCount != 0) {
        z = c;
        c = float4(inflection[control.inflectionCount - 1].xy, 0,0);
    }
    
    float dist;
    
    for(int n = 0; n < 104; ++n) {
        dist = length(z.xy);
        if(dist >= 10) break;
        z = cSqr(z) + c;
    }
    
    float dr = float(length(z.zw));
    float de = 2.0 * dist * log(dist) / dr;
    
    // float g = tanh(clamp(de, -4.0, 4.0)); // tanh(de); // clamp(de, 0.0, 14.0));
    float g = dist / 100.0;    
    if (isnan(de) || isinf(de) || isnan(dr) || isinf(dr) || isnan(dist) || isinf(dist) || isnan(g) || isinf(g))  g = 0;
    
    float cr = control.color1r + (control.color2r - control.color1r) * g;
    float cg = control.color1g + (control.color2g - control.color1g) * g;
    float cb = control.color1b + (control.color2b - control.color1b) * g;

    outTexture.write(float4(cr,cg,cb,1.0),p);
}
