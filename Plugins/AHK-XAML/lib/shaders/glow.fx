// Pulsing Neon Glow Effect
sampler2D implicitInput : register(s0);

// Parameters
float4 GlowColor : register(c0);
float GlowThickness : register(c1); // Offset step (e.g. 0.004)
float PulseSpeed : register(c2);
float Time : register(c3);

float4 main(float2 uv : TEXCOORD0) : COLOR
{
    float4 original = tex2D(implicitInput, uv);
    
    // Sample 8-neighborhood for glow alpha accumulation
    float totalAlpha = 0.0;
    float step = GlowThickness;
    
    totalAlpha += tex2D(implicitInput, uv + float2(-step, -step)).a;
    totalAlpha += tex2D(implicitInput, uv + float2(0, -step)).a;
    totalAlpha += tex2D(implicitInput, uv + float2(step, -step)).a;
    totalAlpha += tex2D(implicitInput, uv + float2(-step, 0)).a;
    totalAlpha += tex2D(implicitInput, uv + float2(step, 0)).a;
    totalAlpha += tex2D(implicitInput, uv + float2(-step, step)).a;
    totalAlpha += tex2D(implicitInput, uv + float2(0, step)).a;
    totalAlpha += tex2D(implicitInput, uv + float2(step, step)).a;
    
    float glowAlpha = totalAlpha / 8.0;
    
    // Dynamic pulse intensity
    float pulse = 0.85 + 0.15 * sin(Time * PulseSpeed);
    
    // The glow is only visible where the original image is thin or transparent
    float finalGlowAlpha = max(0.0, glowAlpha - original.a) * pulse;
    
    float4 glow = float4(GlowColor.rgb, finalGlowAlpha * GlowColor.a);
    
    // Blend original element on top of the glow
    return original + (1.0 - original.a) * glow;
}
