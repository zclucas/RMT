// Water Ripple / Wave Effect
sampler2D implicitInput : register(s0);

// Parameters
float2 Center : register(c0);
float Time : register(c1);      // 0.0 to 1.0 animation time
float Amplitude : register(c2); // Distortion power (e.g. 0.03)
float Frequency : register(c3); // Wave frequency (e.g. 30.0)
float Speed : register(c4);     // Expansion speed (e.g. 1.2)

float4 main(float2 uv : TEXCOORD0) : COLOR
{
    float2 dir = uv - Center;
    float dist = length(dir);
    
    // Normalize direction vector
    float2 normDir = dir / (dist + 0.0001);
    
    // Current wavefront radius
    float waveFront = Time * Speed;
    
    // If wave has reached this pixel
    float d = dist - waveFront;
    float rippleWidth = 0.15;
    
    if (dist < waveFront && d > -rippleWidth)
    {
        // Amplitude fades out over time and at the inner edge of wavefront
        float fade = (1.0 - Time) * (1.0 + d / rippleWidth);
        
        // Sine wave distortion
        float wave = sin(d * Frequency) * Amplitude * fade;
        
        // Displace coordinate
        float2 distortedUv = uv + normDir * wave;
        
        // Sample at distorted coordinates
        float4 color = tex2D(implicitInput, distortedUv);
        
        // Add specular highlights at wave crests
        color.rgb += wave * 0.4;
        return color;
    }
    
    return tex2D(implicitInput, uv);
}
