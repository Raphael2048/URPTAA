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

float2 EncodeVelocityToTexture(float2 V)
{
    //编码范围是-2~2
    //0.499f是中间值，表示速度为0，
    //0是Clear值，表示当前没有速度写入，注意区分和速度为0的区别
    float2 EncodeV =  V.xy * 0.499f + 32767.0f / 65535.0f;
    return EncodeV;
}

Varyings MotionVectorVertex(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.position.xyz);
    output.positionCS = vertexInput.positionCS;
    
    //可能导致某些情况下深度测试不正确
#if UNITY_REVERSED_Z
    output.positionCS.z -= unity_MotionVectorsParams.z * output.positionCS.w;
#else
    output.positionCS.z += unity_MotionVectorsParams.z * output.positionCS.w;
#endif
    
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
    float2 motionVector = (hPos - hPosOld).xy;
    #if UNITY_UV_STARTS_AT_TOP
        motionVector.y = -motionVector.y;
    #endif
    motionVector *= 0.5f;
    if (unity_MotionVectorsParams.y == 0) motionVector = float2(2, 2);
    return EncodeVelocityToTexture(motionVector);
}
#endif
