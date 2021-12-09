namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// Applies relevant settings before rendering transparent objects
    /// </summary>

    internal class TAAUtils
    {
        private const int k_SampleCount = 8;
        public static int sampleIndex { get; private set; }
        public static float HaltonSeq(int index, int radix)
        {
            float result = 0f;
            float fraction = 1f / (float)radix;

            while (index > 0)
            {
                result += (float)(index % radix) * fraction;

                index /= radix;
                fraction /= (float)radix;
            }

            return result;
        }
        
        public static Vector2 GenerateRandomOffset()
        {
            // The variance between 0 and the actual halton sequence values reveals noticeable instability
            // in Unity's shadow maps, so we avoid index 0.
            var offset = new Vector2(
                HaltonSeq((sampleIndex & 1023) + 1, 2) - 0.5f,
                HaltonSeq((sampleIndex & 1023) + 1, 3) - 0.5f
            );

            if (++sampleIndex >= k_SampleCount)
                sampleIndex = 0;

            return offset;
        }

        public static void GetJitteredPerspectiveProjectionMatrix(Camera camera, out Vector4 jitterPixels, out Matrix4x4 jitteredMatrix)
        {
            jitterPixels.z = sampleIndex;
            jitterPixels.w = k_SampleCount;
            var v = GenerateRandomOffset();
            jitterPixels.x = v.x;
            jitterPixels.y = v.y;
            var offset = new Vector2(
                jitterPixels.x / camera.pixelWidth,
                jitterPixels.y / camera.pixelHeight
            );
            jitteredMatrix = camera.projectionMatrix;
            jitteredMatrix.m02 += offset.x * 2;
            jitteredMatrix.m12 += offset.y * 2;
        }
    }
}
