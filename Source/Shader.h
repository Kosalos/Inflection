#ifndef Shader_h
#define Shader_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

#define SIZE 1000
#define MAX_INFLECTIONS 8

struct Control {
    bool centering;
    bool julia;
    int inflectionCount;
    float centerX,centerY;

    vector_float2 sCenter;
    float zoom;
    
    float color1r,color1g,color1b;
    float color2r,color2g,color2b;
};

#endif

