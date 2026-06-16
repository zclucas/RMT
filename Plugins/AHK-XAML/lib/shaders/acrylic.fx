// Acrylic Frosted Glass Effect
sampler2D implicitInput : register(s0);

// Parameters
float4 TintColor : register(c0);   // RGBA tint color
float NoiseAmount : register(c1);  // Intensity of frosted noise (e.g. 0.03)
float BlurRadius : register(c2);   // Blur offset multiplier (e.g. 0.002)

float hash(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

float4 main(float2 uv : TEXCOORD0) : COLOR
{
    // Perform a 9-tap blur
    float2 step = BlurRadius * 0.5;
    float4 blurred = float4(0,0,0,0);
    
    blurred += tex2D(implicitInput, uv + float2(-step.x, -step.y)) * 0.094;
    blurred += tex2D(implicitInput, uv + float2(0.0, -step.y)) * 0.118;
    blurred += tex2D(implicitInput, uv + float2(step.x, -step.y)) * 0.094;
    
    blurred += tex2D(implicitInput, uv + float2(-step.x, 0.0)) * 0.118;
    blurred += tex2D(implicitInput, uv + float2(0.0, 0.0)) * 0.148;
    blurred += tex2D(implicitInput, uv + float2(step.x, 0.0)) * 0.118;
    
    blurred += tex2D(implicitInput, uv + float2(-step.x, step.y)) * 0.094;
    blurred += tex2D(implicitInput, uv + float2(0.0, step.y)) * 0.118;
    blurred += tex2D(implicitInput, uv + float2(step.x, step.y)) * 0.094;
    
    // Blend with the TintColor
    float3 colored = lerp(blurred.rgb, TintColor.rgb, TintColor.a);
    
    // Add frosted grain noise
    float grain = hash(uv * 1000.0) - 0.5;
    colored += grain * NoiseAmount;
    
    return float4(colored, blurred.a);
}
