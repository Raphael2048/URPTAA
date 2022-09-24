#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

float4 _Params;
#define _Jitter _Params.xy
#define _Reset _Params.z

float2 DecodeVelocityFromTexture(float2 EncodedV)
{
    const float InvDiv = 1.0f / (0.499f);
    float2 V = EncodedV.xy * InvDiv - 32767.0f / 65535.0f * InvDiv;
    return V;
}

Texture2D _CameraDepthTexture;
float4 _CameraDepthTexture_TexelSize;
Texture2D _InputHistoryTexture;
Texture2D _InputTexture;
float4 _InputTexture_TexelSize;
Texture2D _CameraMotionVectorsTexture;

static const int2 kOffsets3x3[9] =
{
    int2(-1, -1),
    int2( 0, -1),
    int2( 1, -1),
    int2(-1,  0),
    int2( 0,  0),
    int2( 1,  0),
    int2(-1,  1),
    int2( 0,  1),
    int2( 1,  1),
};

float GetSceneColorHdrWeight(float4 SceneColor)
{
    return rcp(SceneColor.x + 4);
}

float3 FastToneMap(in float3 color)
{
    return color.rgb * rcp(color.rgb + 1.0f);
}

float3 FastToneUnmap(in float3 color)
{
    return color.rgb * rcp(1.0f - color.rgb);
}

// Unity自带的转换函数，会在Metal上出错，尚不知道原因
float3 RGB2YCoCg( float3 RGB )
{
    float Y  = dot( RGB, float3(  1, 2,  1 ) );
    float Co = dot( RGB, float3(  2, 0, -2 ) );
    float Cg = dot( RGB, float3( -1, 2, -1 ) );
	
    float3 YCoCg = float3( Y, Co, Cg );
    return YCoCg;
}

float3 YCoCg2RGB( float3 YCoCg )
{
    float Y  = YCoCg.x * 0.25;
    float Co = YCoCg.y * 0.25;
    float Cg = YCoCg.z * 0.25;

    float R = Y + Co - Cg;
    float G = Y + Cg;
    float B = Y - Co - Cg;

    float3 RGB = float3( R, G, B );
    return RGB;
}

float3 TransformColorToTAASpace(float3 Color)
{
    return RGB2YCoCg(Color);
}

float3 TransformTAASpaceBack(float3 Color)
{
    return YCoCg2RGB(Color);
}

float3 ClipHistory(float3 History, float3 BoxMin, float3 BoxMax)
{
    float3 Filtered = (BoxMin + BoxMax) * 0.5f;
    float3 RayOrigin = History;
    float3 RayDir = Filtered - History;
    RayDir = abs( RayDir ) < (1.0/65536.0) ? (1.0/65536.0) : RayDir;
    float3 InvRayDir = rcp( RayDir );
        
    float3 MinIntersect = (BoxMin - RayOrigin) * InvRayDir;
    float3 MaxIntersect = (BoxMax - RayOrigin) * InvRayDir;
    float3 EnterIntersect = min( MinIntersect, MaxIntersect );
    float ClipBlend = max( EnterIntersect.x, max(EnterIntersect.y, EnterIntersect.z ));
    ClipBlend = saturate(ClipBlend);
    return lerp(History, Filtered, ClipBlend);
}

float2 GetMotionVector(float2 screenPos, float depth)
{
    PositionInputs inputs = GetPositionInput(screenPos, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
    float4 curClipPos = mul(UNITY_MATRIX_UNJITTERED_VP, float4(inputs.positionWS, 1));
    curClipPos /= curClipPos.w;

    float4 preClipPos = mul(UNITY_MATRIX_PREV_VP, float4(inputs.positionWS, 1));
    preClipPos /= preClipPos.w;

    float2 motionVector = curClipPos.xy - preClipPos.xy;
    #if UNITY_UV_STARTS_AT_TOP
    motionVector.y = -motionVector.y;
    #endif
    return motionVector * 0.5;
}

float2 GetClosestFragment(float2 uv, float depth)
{
    float2 k = _CameraDepthTexture_TexelSize.xy;
    const float4 neighborhood = float4(
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv - k, 0).r,
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv + float2(k.x, -k.y), 0).r,
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv + float2(-k.x, k.y), 0).r,
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv + k, 0).r
    );
    #if UNITY_REVERSED_Z
    #define COMPARE_DEPTH(a, b) step(b, a)
    #else
    #define COMPARE_DEPTH(a, b) step(a, b)
    #endif
    
    float3 result = float3(0.0, 0.0, depth);
    result = lerp(result, float3(-1.0, -1.0, neighborhood.x), COMPARE_DEPTH(neighborhood.x, result.z));
    result = lerp(result, float3( 1.0, -1.0, neighborhood.y), COMPARE_DEPTH(neighborhood.y, result.z));
    result = lerp(result, float3(-1.0,  1.0, neighborhood.z), COMPARE_DEPTH(neighborhood.z, result.z));
    result = lerp(result, float3( 1.0,  1.0, neighborhood.w), COMPARE_DEPTH(neighborhood.w, result.z));
    return (uv + result.xy * k);
}

