// Moving Multi-Color Gradient Effect
sampler2D implicitInput : register(s0);

// Parameters
float4 Color1 : register(c0);
float4 Color2 : register(c1);
float4 Color3 : register(c2);
float Angle : register(c3);     // Angle in degrees
float Speed : register(c4);     // Speed of color shifting
float Time : register(c5);
float Brightness : register(c6);

float4 main(float2 uv : TEXCOORD0) : COLOR
{
    float4 original = tex2D(implicitInput, uv);
    
    // Convert angle to radians and rotate coords
    float rad = Angle * 3.14159265 / 180.0;
    float2 rotUv = float2(
        uv.x * cos(rad) - uv.y * sin(rad),
        uv.x * sin(rad) + uv.y * cos(rad)
    );
    
    // Calculate shifting phase
    float phase = rotUv.x - Time * Speed;
    
    // Blending weights
    float w1 = (sin(phase * 6.28318) + 1.0) * 0.5;
    float w2 = (cos(phase * 3.14159) + 1.0) * 0.5;
    
    float4 gradientColor = lerp(Color1, Color2, w1);
    gradientColor = lerp(gradientColor, Color3, w2);
    
    // Apply as a color overlay matching original texture's alpha channel
    float4 finalColor = float4(gradientColor.rgb * Brightness, original.a * gradientColor.a);
    
    return finalColor * original.a;
}
