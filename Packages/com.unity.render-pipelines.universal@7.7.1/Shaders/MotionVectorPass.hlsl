#ifndef UNIVERSAL_MOTION_VECTOR_INCLUDED
#define UNIVERSAL_MOTION_VECTOR_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

struct Attributes
{
    float4 position     : POSITION;
    float2 texcoord     : TEXCOORD0;
    float3 positionLast :TEXCOORD4;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float2 uv           : TEXCOORD0;
    float4 positionCS   : SV_POSITION;
    float4 transferPos  : TEXCOORD1;
    float4 transferPosOld : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

Varyings MotionVectorVertex(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.positionCS = TransformObjectToHClip(input.position.xyz);
    output.transferPos = mul(UNITY_MATRIX_UNJITTERED_VP, mul(GetObjectToWorldMatrix(), float4(input.position.xyz, 1.0)));
    if(unity_MotionVectorsParams.x > 0)
    {
        output.transferPosOld = mul(UNITY_MATRIX_PREV_VP, mul(unity_MatrixPreviousM, float4(input.positionLast.xyz, 1.0)));
    }
    else
    {
        output.transferPosOld = mul(UNITY_MATRIX_PREV_VP, mul(unity_MatrixPreviousM, float4(input.position.xyz, 1.0)));
    }
    return output;
    
}

float2 MotionVectorFragment(Varyings input) : SV_TARGET
{
    float3 hPos = (input.transferPos.xyz / input.transferPos.w);
    float3 hPosOld = (input.transferPosOld.xyz / input.transferPosOld.w);
    float2 motionVector = hPos - hPosOld;
    #if UNITY_UV_STARTS_AT_TOP
        motionVector.y = -motionVector.y;
    #endif
    if (unity_MotionVectorsParams.y == 0) return float2(1, 0);
    return motionVector * 0.5;
    
}
#endif
