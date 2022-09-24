using System.Collections.Generic;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.Universal;

namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// Applies relevant settings before rendering transparent objects
    /// </summary>

    internal class MotionVectorPass : ScriptableRenderPass
    {

        const string m_ProfilerTag = "Motion Vector";
        ProfilingSampler m_ProfilingSampler = new ProfilingSampler(m_ProfilerTag);
        private RenderTargetHandle motionVector, depth;
        private Matrix4x4 ViewProjectionMatrix;
        private bool first = false;
        
        FilteringSettings m_FilteringSettings;
        private ShaderTagId m_ShaderTagId;

        public MotionVectorPass()
        {
            renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
            m_FilteringSettings = new FilteringSettings(RenderQueueRange.opaque);
            m_ShaderTagId = new ShaderTagId("MotionVectors");
        }

        public void Setup(ref RenderingData renderingData, RenderTargetHandle identifier, RenderTargetHandle depth)
        {
            motionVector = identifier;
            this.depth = depth;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            cameraTextureDescriptor.graphicsFormat = GraphicsFormat.R16G16_UNorm;
            cameraTextureDescriptor.depthBufferBits = 0;
            cameraTextureDescriptor.msaaSamples = 1;
            cmd.GetTemporaryRT(motionVector.id, cameraTextureDescriptor);
            ConfigureTarget(motionVector.Identifier(), depth.Identifier());
            ConfigureClear(ClearFlag.Color, Color.black);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);
            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                var proj = GL.GetGPUProjectionMatrix(renderingData.cameraData.GetUnJitteredProjectionMatrix(), true);
                var view = renderingData.cameraData.GetViewMatrix();
                if (first)
                {
                    ViewProjectionMatrix = proj * view;
                    cmd.SetGlobalMatrix(ShaderPropertyId.prevViewAndProjectionMatrix, ViewProjectionMatrix);
                }
                else
                {
                    cmd.SetGlobalMatrix(ShaderPropertyId.prevViewAndProjectionMatrix, ViewProjectionMatrix);
                    ViewProjectionMatrix = proj * view;
                }
                
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                if (renderingData.cameraData.antialiasingQuality >= AntialiasingQuality.Medium)
                {
                    //必须加上这个设置，否者无法获取上一帧中的数据
                    renderingData.cameraData.camera.depthTextureMode |= (DepthTextureMode.MotionVectors | DepthTextureMode.Depth);
                    SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                    DrawingSettings drawingSettings = CreateDrawingSettings(m_ShaderTagId, ref renderingData, sortingCriteria);
                    drawingSettings.perObjectData = PerObjectData.MotionVectors;
                    context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
                }
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
