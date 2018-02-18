#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

constant float er = 1.0e10;

float2 cMul(float a, float2 b){
    return float2(a * b.x - a * b.y, a * b.y + a * b.x);
}

float2 cMul(float2 a, float2 b){
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

float2 cSqr(float2 a)
{
    return cMul(a, a);
}

float4 cMul(float4 a, float4 b)
{
    return float4(cMul(a.xy, b.xy), cMul(a.xy, b.zw) + cMul(a.zw, b.xy));
}

float4 cSqr(float4 a)
{
    return cMul(a, a);
}

kernel void inflectionShader
(
    texture2d<float, access::write> outTexture [[texture(0)]],
    constant Control &control [[buffer(0)]],
    constant float3 *inflection [[buffer(1)]],
    uint2 p [[thread_position_in_grid]])
{
    float2 texcoord_ = control.sCenter + float2(p.x,p.y) * control.zoom;
    float4 c = float4(texcoord_, 1, 0.0);
    
    if (control.count > 0) {
        float r = inflection[0].z;
        float4 f = float4(inflection[0].xy, 0.0, 0.0);
        float4 d = c;
        
        if (!control.centering) {
            d -= f;
        }
        
        c = cSqr(d / r) * r + f;
    }
    
    for (int i = 1; i < control.count; ++i)  {
        float r = inflection[i].z;
        float4 f = float4(inflection[i].xy, 0.0, 0.0);
        float4 d = c - f;
        c = cSqr(d / r) * r + f;
    }
    
    //float4 icolor = float4(0,0,0,1);
    
    float4 z = float4(0,0,0,0);
    
    if(control.julia && control.count != 0) {
        z = c;
        c = float4(inflection[control.count - 1].xy, 0,0);
    }
    
    float dist;
    
    for(int n = 0; n < 104; ++n) {
//        if (dot(z.xy, z.xy) >= 10) break;
        
        dist = length(z.xy);
        if(dist >= 10) break;
        z = cSqr(z) + c;
    }
    
    float dr = float(length(z.zw));
    float de = 2.0 * dist * log(dist) / dr;
    
//    float g = tanh(clamp(de, -4.0, 4.0)); // tanh(de); // clamp(de, 0.0, 14.0));
    float g = dist / 100.0; // tanh(de); //dist; // tanh(clamp(r, -4.0, 4.0)); // tanh(de); // clamp(de, 0.0, 14.0));
    
    if (isnan(de) || isinf(de) || isnan(dr) || isinf(dr) || isnan(dist) || isinf(dist) || isnan(g) || isinf(g))  g = 0;
    
//    float4 grey = float4(float3(g), 1.0);
//    float4 blue = float4(0.5, 0.5, 1.0, 1.0);
//    icolor = grey; // length(texcoord_ - control.dragging.xy) < control.dragging.z ? blue * grey : grey;
    
    outTexture.write(float4(float3(g), 1.0),p);

    //outTexture.write(float4(0,1,1,1),p);
}

//float2 tc = float2(p.x,p.y);
//float2 texcoord_ = control.sCenter + cMul(control.zoom, tc);
//float px = control.zoom; // float(length(float4(control.sRadius, control.sRadius) )); //  * float4(dfdx(float2(control.aspect) * tc), dfdy(float2(control.aspect) * tc))));
//float4 c = float4(texcoord_, px, 0.0);
//
//if (0 < control.count) {
//    float r = inflection[0].z;
//    float4 f = float4(inflection[0].xy, 0.0, 0.0);
//    float4 d = c;
//
//    if (!control.centering) {
//        d -= f;
//    }
//
//    c = cSqr(d / r) * r + f;
//}
//
//for (int i = 1; i < control.count && i < MAXCOUNT; ++i)  {
//    float r = inflection[i].z;
//    float4 f = float4(inflection[i].xy, 0.0, 0.0);
//    float4 d = c - f;
//    c = cSqr(d / r) * r + f;
//}
//
//float4 icolor = float4(0,0,0,1);
//
//int n = 0;
//float4 z = control.julia && control.count != 0 ? c : float4(0.0, 0.0, 0.0, 0.0);
//
//c = control.julia && control.count != 0 ? float4(inflection[control.count - 1].xy, 0.0, 0.0) : c;
//
//for (n = 0; n < 1024; ++n) {
//    if (dot(z.xy, z.xy) >= er) {
//        float r = float(length(z.xy));
//        float dr = float(length(z.zw));
//        float de = 2.0 * r * log(r) / dr;
//        float g = tanh(clamp(de, 0.0, 4.0));
//        if (isnan(de) || isinf(de) || isnan(dr) || isinf(dr) || isnan(r) || isinf(r) || isnan(g) || isinf(g))
//            g = 0;
//
//            float4 grey = float4(float3(g), 1.0);
//            float4 blue = float4(0.5, 0.5, 1.0, 1.0);
//
//            icolor = length(texcoord_ - control.dragging.xy) < control.dragging.z ? blue * grey : grey;
//
//            outTexture.write(icolor,p);
//            return;
//    }
//
//    z = cSqr(z) + c;
//}
//
//outTexture.write(float4(1.0, 0.0, 0.0, 1.0),p);


//for (n = 0; n < 1024; ++n) {
//    if (dot(z.xy, z.xy) >= er)
//        break;
//    z = cSqr(z) + c;
//}
//
//if (dot(z.xy, z.xy) < er) {
//    icolor = float4(1.0, 0.0, 0.0, 1.0);
//}
//else {
//    float r = float(length(z.xy));
//    float dr = float(length(z.zw));
//    float de = 2.0 * r * log(r) / dr;
//    float g = tanh(clamp(de, 0.0, 4.0));
//    if (isnan(de) || isinf(de) || isnan(dr) || isinf(dr) || isnan(r) || isinf(r) || isnan(g) || isinf(g))
//        g = 0;
//
//        float4 grey = float4(float3(g), 1.0);
//        float4 blue = float4(0.5, 0.5, 1.0, 1.0);
//
//        icolor = length(texcoord_ - control.dragging.xy) < control.dragging.z ? blue * grey : grey;
//        }

