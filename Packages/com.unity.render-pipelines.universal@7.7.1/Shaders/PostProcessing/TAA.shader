Shader "Hidden/Universal Render Pipeline/TAA"
{
    Properties
    {
        _MainTex("Source", 2D) = "white" {}
    }

    HLSLINCLUDE
    
        #pragma target 3.5
        #include "TAA.hlsl"

        struct ProceduralAttributes
        {
            uint vertexID : VERTEXID_SEMANTIC;
        };
        
        struct ProceduralVaryings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD;
        };
        
        ProceduralVaryings ProceduralVert (ProceduralAttributes input)
        {
            ProceduralVaryings output;
            output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
            output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
            return output;
        }

        float4 TAAFrag(Varyings input) : SV_Target
        {
            float2 uv = input.uv - _Jitter;
            float3 color = TransformColorToTAASpace(SAMPLE_TEXTURE2D_X(_InputTexture, sampler_LinearClamp, uv));
            if(_Reset > 0.0f)
            {
                return float4(TransformTAASpaceBack(color), 1);
            }
        #if _USE_MOTION_VECTOR_BUFFER
            float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, input.uv);
            float2 Motion = GetMotionVector(input.positionCS, depth);
            float2 closest = GetClosestFragment(input.uv, depth);
            float2 SampleVelocity = SAMPLE_TEXTURE2D(_CameraMotionVectorsTexture, sampler_PointClamp, closest).xy;
            if(SampleVelocity.x > 0)
                Motion = DecodeVelocityFromTexture(SampleVelocity);
        #else
            float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, input.uv);
            float2 Motion = GetMotionVector(input.positionCS, depth).xy;
        #endif
            float2 HistoryUV = input.uv - Motion;
            float3 HistoryColor = TransformColorToTAASpace(_InputHistoryTexture.Sample(sampler_LinearClamp, HistoryUV));
            float3 M1 = 0.0f;
            float3 M2 = 0.0f;
            UNITY_UNROLL
            for(int k = 0; k < 9; k++)
            {
                float3 C = TransformColorToTAASpace(_InputTexture.Sample(sampler_PointClamp, uv, kOffsets3x3[k]));
                M1 += C;
                M2 += C * C;
            }
            M1 *= (1 / 9.0f);
            M2 *= (1 / 9.0f);
            float3 StdDev = sqrt(abs(M2 - M1 * M1));
            float3 AABBMin = M1 - 1.25 * StdDev;
            float3 AABBMax = M1 + 1.25 * StdDev;
            
            HistoryColor = ClipHistory(HistoryColor, AABBMin, AABBMax);
            float BlendFactor = saturate(0.05 + (abs(Motion.x) + abs(Motion.y)) * 10);
            float3 result = lerp(HistoryColor, color, BlendFactor);
            result = TransformTAASpaceBack(result);
            result = -min(-result, 0);
            return float4(result, 1);
        }
    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZTest Always ZWrite Off Cull Off
        
        Pass
        {
            Name "TAA"
            HLSLPROGRAM
                #pragma multi_compile _ _USE_MOTION_VECTOR_BUFFER
                #pragma vertex ProceduralVert
                #pragma fragment TAAFrag
            ENDHLSL
        }
    }
}
