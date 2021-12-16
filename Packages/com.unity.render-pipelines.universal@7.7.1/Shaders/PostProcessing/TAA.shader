Shader "Hidden/Universal Render Pipeline/TAA"
{
    Properties
    {
        _MainTex("Source", 2D) = "white" {}
    }

    HLSLINCLUDE
    
        #pragma target 3.5

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

        
        Texture2D _CameraDepthTexture;
        float4 _CameraDepthTexture_TexelSize;
        Texture2D _InputHistoryTexture;
        Texture2D _InputTexture;
        float4 _InputTexture_TexelSize;
        Texture2D _CameraMotionVectorsTexture;
    
        float4 _Params;
        #define _Jitter _Params.xy
        #define _Reset _Params.z

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
    

        float2 CameraMotionFrag(Varyings input) : SV_Target
        {
            float depth = _CameraDepthTexture.Load(int3(input.positionCS.xy, 0));
            PositionInputs inputs = GetPositionInput(input.positionCS.xy, _ScreenParams.zw - 1, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
            // return float4(input.positionCS.xy * (_ScreenParams.zw - 1), 0, 0);

            float4 curClipPos = mul(UNITY_MATRIX_UNJITTERED_VP, float4(inputs.positionWS, 1));
            curClipPos /= curClipPos.w;

            float4 preClipPos = mul(UNITY_MATRIX_PREV_VP, float4(inputs.positionWS, 1));
            preClipPos /= preClipPos.w;

            float2 motionVector = curClipPos - preClipPos;
#if UNITY_UV_STARTS_AT_TOP
            motionVector.y = -motionVector.y;
#endif
            return motionVector * 0.5;
        }


        float2 GetClosestFragment(float2 uv)
        {
            float2 k = _CameraDepthTexture_TexelSize.xy;
            const float4 neighborhood = float4(
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv - k),
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv + float2(k.x, -k.y)),
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv + float2(-k.x, k.y)),
                SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv + k)
            );
        #if UNITY_REVERSED_Z
            #define COMPARE_DEPTH(a, b) step(b, a)
        #else
            #define COMPARE_DEPTH(a, b) step(a, b)
        #endif
            float3 result = float3(0.0, 0.0, SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv));
            result = lerp(result, float3(-1.0, -1.0, neighborhood.x), COMPARE_DEPTH(neighborhood.x, result.z));
            result = lerp(result, float3( 1.0, -1.0, neighborhood.y), COMPARE_DEPTH(neighborhood.y, result.z));
            result = lerp(result, float3(-1.0,  1.0, neighborhood.z), COMPARE_DEPTH(neighborhood.z, result.z));
            result = lerp(result, float3( 1.0,  1.0, neighborhood.w), COMPARE_DEPTH(neighborhood.w, result.z));
            return (uv + result.xy * k);
        }

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
    
        float3 FastToneMap(in float3 color)
        {

            return color.rgb * rcp(color.rgb + 1.0f);
        }

        float3 FastToneUnmap(in float3 color)
        {
            return color.rgb * rcp(1.0f - color.rgb);
        }
    

        void TAAFrag(Varyings input, out float3 ResultOut[2] : SV_Target)
        {
            float2 uv = input.uv - _Jitter;
            float3 color = SAMPLE_TEXTURE2D_X(_InputTexture, sampler_LinearClamp, uv);
            if(_Reset)
            {
                ResultOut[0] = color;
                ResultOut[1] = color;
                return;
            }
            float2 closest = GetClosestFragment(input.uv);
            float2 Motion = SAMPLE_TEXTURE2D(_CameraMotionVectorsTexture, sampler_LinearClamp, closest).xy;
            // ResultOut[0] = float4(Motion * 10, 0, 0);
            // ResultOut[1] = float4(Motion * 10, 0, 0);
            // return;
            float2 HistoryUV = input.uv - Motion;
            float3 HistoryColor = _InputHistoryTexture.Sample(sampler_LinearClamp, HistoryUV);

            float3 AABBMin, AABBMax;
            AABBMin = AABBMax = RGBToYCoCg(FastToneMap(color));
            UNITY_UNROLL
            for(int k = 0; k < 9; k++)
            {
                float3 C = RGBToYCoCg(FastToneMap(_InputTexture.Sample(sampler_PointClamp, uv, kOffsets3x3[k])));
                AABBMin = min(AABBMin, C);
                AABBMax = max(AABBMax, C);
            }
            float3 HistoryColorYCoCg = RGBToYCoCg(FastToneMap(HistoryColor));
            HistoryColor = FastToneUnmap(YCoCgToRGB(ClipHistory(HistoryColorYCoCg, AABBMin,AABBMax)));

            float BlendFactor = saturate(0.05 + (abs(Motion.x) + abs(Motion.y)) * 10);
            float3 result = lerp(HistoryColor, color, BlendFactor);
            ResultOut[0] = result;
            ResultOut[1] = result;
            return;
        }
        

    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "CameraMotionVector"

            HLSLPROGRAM
                #pragma vertex ProceduralVert
                #pragma fragment CameraMotionFrag
            ENDHLSL
        }
        
        Pass
        {
            Name "TAA"

            HLSLPROGRAM
                #pragma vertex ProceduralVert
                #pragma fragment TAAFrag
            ENDHLSL
        }
    }
}
