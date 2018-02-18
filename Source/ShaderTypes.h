#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

#define SIZE 1024
#define MAXCOUNT 8

struct Control {
    bool centering;
    bool julia;
    int count;
    float centerX,centerY;
    float radiusX,radiusY;

    vector_float2 sCenter;
    float zoom;
    vector_float3 dragging;
};

#endif /* ShaderTypes_h */

