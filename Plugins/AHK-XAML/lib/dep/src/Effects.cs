// =============================================================================
// Shader effects (ENABLE_SHADERS)
// =============================================================================
#if ENABLE_SHADERS

using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using System.Reflection;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Markup;
using Color = System.Windows.Media.Color;

namespace AhkEffects
{
    public static class Bytecodes
    {
        public static readonly string Acrylic = "AAL///7/QQBDVEFCHAAAANcAAAAAAv//BAAAABwAAAAAAQAA0AAAAGwAAAACAAIAAQAKAHgAAAAAAAAAiAAAAAIAAQABAAYAeAAAAAAAAACUAAAAAgAAAAEAAgCgAAAAAAAAALAAAAADAAAAAQACAMAAAAAAAAAAQmx1clJhZGl1cwCrAAADAAEAAQABAAAAAAAAAE5vaXNlQW1vdW50AFRpbnRDb2xvcgCrqwEAAwABAAQAAQAAAAAAAABpbXBsaWNpdElucHV0AKurBAAMAAEAAQABAAAAAAAAAHBzXzJfMABNaWNyb3NvZnQgKFIpIEhMU0wgU2hhZGVyIENvbXBpbGVyIDEwLjEAq1EAAAUDAA+gAAAAP/yp8T0Sg8A9UI0XPlEAAAUEAA+gAAB6RDMz/kKa2ZtDAAAAAFEAAAUFAA+gg/kiPgAAAD/bD8lA2w9JwFEAAAUGAA+gjO4qRwAAAAAAAAAAAAAAAFEAAAUHAA+gAQ3QtWELtrerqio7iYiIOVEAAAUIAA+gq6qqvAAAAL4AAIA/AAAAPx8AAAIAAACAAAADsB8AAAIAAACQAAgPoAEAAAIAAAGAAAAAsAEAAAIBAAiAAwAAoAQAAAQAAAKAAgAAoAEA/4EAAFWwBAAABAEAA4ACAACgAQD/gQAA5LAEAAAEAgABgAIAAKABAP+AAAAAsAQAAAQCAAKAAgAAoAEA/4EAAFWwBAAABAMAAYACAACgAQD/gQAAALABAAACAwACgAAAVbAEAAAEBAABgAIAAKABAP+AAAAAsAEAAAIEAAKAAABVsAQAAAQFAAGAAgAAoAEA/4EAAACwBAAABAUAAoACAACgAQD/gAAAVbABAAACBgABgAAAALAEAAAEBgACgAIAAKABAP+AAABVsAQAAAQHAAOAAgAAoAEA/4AAAOSwQgAAAwAAD4AAAOSAAAjkoEIAAAMBAA+AAQDkgAAI5KBCAAADAgAPgAIA5IAACOSgQgAAAwMAD4ADAOSAAAjkoEIAAAMIAA+AAADksAAI5KBCAAADBAAPgAQA5IAACOSgQgAAAwUAD4AFAOSAAAjkoEIAAAMGAA+ABgDkgAAI5KBCAAADBwAPgAcA5IAACOSgBQAAAwAAD4AAAOSAAwBVoAQAAAQAAA+AAQDkgAMAqqAAAOSABAAABAAAD4ACAOSAAwCqoAAA5IAEAAAEAAAPgAMA5IADAFWgAADkgAQAAAQAAA+ACADkgAMA/6AAAOSABAAABAAAD4AEAOSAAwBVoAAA5IAEAAAEAAAPgAUA5IADAKqgAADkgAQAAAQAAA+ABgDkgAMAVaAAAOSABAAABAAAD4AHAOSAAwCqoAAA5IASAAAEAQAHgAAA/6AAAOSgAADkgAUAAAMCAAOAAADksAQAAKBaAAAEAQAIgAEA5IAEAMmgBAD/oAQAAAQBAAiAAQD/gAUAAKAFAFWgEwAAAgEACIABAP+ABAAABAEACIABAP+ABQCqoAUA/6AlAAAEAgACgAEA/4AHAOSgCADkoAUAAAMBAAiAAgBVgAYAAKATAAACAQAIgAEA/4ACAAADAQAIgAEA/4ADAAChBAAABAAAB4ABAP+AAQAAoAEA5IABAAACAAgPgAAA5ID//wAA";

        public static readonly string Confetti = "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";

        public static readonly string Glow = "AAL///7/SABDVEFCHAAAAPMAAAAAAv//BQAAABwAAAAAAQAA7AAAAIAAAAACAAAAAQACAIwAAAAAAAAAnAAAAAIAAQABAAYArAAAAAAAAAC8AAAAAgACAAEACgCsAAAAAAAAAMcAAAACAAMAAQAOAKwAAAAAAAAAzAAAAAMAAAABAAIA3AAAAAAAAABHbG93Q29sb3IAq6sBAAMAAQAEAAEAAAAAAAAAR2xvd1RoaWNrbmVzcwCrqwAAAwABAAEAAQAAAAAAAABQdWxzZVNwZWVkAFRpbWUAaW1wbGljaXRJbnB1dACrqwQADAABAAEAAQAAAAAAAABwc18yXzAATWljcm9zb2Z0IChSKSBITFNMIFNoYWRlciBDb21waWxlciAxMC4xAKtRAAAFBAAPoAAAAAAAAIC/AACAPwAAAD5RAAAFBQAPoJqZGT6amVk/AAAAAAAAAABRAAAFBgAPoIP5Ij4AAAA/2w/JQNsPScBRAAAFBwAPoAEN0LVhC7a3q6oqO4mIiDlRAAAFCAAPoKuqqrwAAAC+AACAPwAAAD8fAAACAAAAgAAAA7AfAAACAAAAkAAID6ABAAACAAABgAAAALACAAADAAACgAAAVbABAAChAgAAAwEAA4AAAOSwAQAAoQIAAAMCAAGAAAAAsAEAAKACAAADAgACgAAAVbABAAChAQAAAgMAAYABAAChAQAAAgMAAoAEAACgAgAAAwMAA4ADAOSAAADksAIAAAMEAAGAAAAAsAEAAKABAAACBAACgAAAVbABAAACBQAIgAEAAKAEAAAEBQADgAUA/4AEAMmgAADksAEAAAIGAAGAAAAAsAIAAAMGAAKAAABVsAEAAKACAAADBwADgAAA5LABAACgQgAAAwAAD4AAAOSAAAjkoEIAAAMBAA+AAQDkgAAI5KBCAAADAgAPgAIA5IAACOSgQgAAAwMAD4ADAOSAAAjkoEIAAAMIAA+AAADksAAI5KBCAAADBAAPgAQA5IAACOSgQgAAAwUAD4AFAOSAAAjkoEIAAAMGAA+ABgDkgAAI5KBCAAADBwAPgAcA5IAACOSgBQAAAwAAD4AAAOSAAwBVoAQAAAQAAA+AAQDkgAMAqqAAAOSABAAABAAAD4ACAOSAAwCqoAAA5IAEAAAEAAAPgAMA5IADAFWgAADkgAQAAAQAAA+ACADkgAMA/6AAAOSABAAABAAAD4AEAOSAAwBVoAAA5IAEAAAEAAAPgAUA5IADAKqgAADkgAQAAAQAAA+ABgDkgAMAVaAAAOSABAAABAAAD4AHAOSAAwCqoAAA5IASAAAEAQAHgAAA/6AAAOSgAADkgAUAAAMCAAOAAADksAQAAKBaAAAEAQAIgAIA5IAEAMmgBAD/oAQAAAQBAAiAAQD/gAUAAKAFAFWgEwAAAgEACIABAP+ABAAABAEACIABAP+ABQCqoAUA/6AlAAAEAgACgAEA/4AHAOSgCADkoAUAAAMBAAiAAgBVgAYAAKATAAACAQAIgAEA/4ACAAADAQAIgAEA/4ADAAChBAAABAAAB4ABAP+AAQAAoAEA5IABAAACAAgPgAAA5ID//wAA";

        public static readonly string Gradient = "AAL///7/WQBDVEFCHAAAADcBAAAAAv//CAAAABwAAAAAAQAAMAEAALwAAAACAAMAAQAOAMQAAAAAAAAA1AAAAAIABgABABoAxAAAAAAAAADfAAAAAgAAAAEAAgDoAAAAAAAAAPgAAAACAAEAAQAGAOgAAAAAAAAA/wAAAAIAAgABAAoA6AAAAAAAAAAGAQAAAgAEAAEAEgDEAAAAAAAAAAwBAAACAAUAAQAWAMQAAAAAAAAAEQEAAAMAAAABAAIAIAEAAAAAAABBbmdsZQCrqwAAAwABAAEAAQAAAAAAAABCcmlnaHRuZXNzAENvbG9yMQCrqwEAAwABAAQAAQAAAAAAAABDb2xvcjIAQ29sb3IzAFNwZWVkAFRpbWUAaW1wbGljaXRJbnB1dACrBAAMAAEAAQABAAAAAAAAAHBzXzJfMABNaWNyb3NvZnQgKFIpIEhMU0wgU2hhZGVyIENvbXBpbGVyIDEwLjEAq1EAAAUHAA+gYQs2OwAAAD/bD8lA2w9JwFEAAAUIAA+g8v9/PwAAAD8AAIA/8v//PlEAAAUJAA+gAQ3QtWELtrerqio7iYiIOVEAAAUKAA+gq6qqvAAAAL4AAIA/AAAAPx8AAAIAAACAAAADsB8AAAIAAACQAAgPoEIAAAMAAA+AAADksAAI5KABAAACAAADgAcA5KAEAAAEAAABgAMAAKAAAACAAABVgBMAAAIAAAGAAAAAgAQAAAQAAAGAAAAAgAcAqqAHAP+gJQAABAEAA4AAAACACQDkoAoA5KAFAAADAAABgAEAVYAAAFWwBAAABAAAAYAAAACwAQAAgAAAAIEBAAACAQABgAUAAKAEAAAEAAABgAEAAIAEAAChAAAAgAQAAAQAAAKAAAAAgAgAAKAIAFWgBAAABAAAAYAAAACACAD/oAgAVaATAAACAAABgAAAAIAEAAAEAAABgAAAAIAHAKqgBwD/oCUAAAQBAAGAAAAAgAkA5KAKAOSgAgAAAwAAAYABAACACACqoBMAAAIAAAKAAABVgAQAAAQAAAKAAABVgAcAqqAHAP+gJQAABAEAAoAAAFWACQDkoAoA5KACAAADAAACgAEAVYAIAKqgBQAAAwAAA4AAAOSABwBVoAEAAAIBAA+AAADkoAIAAAMBAA+AAQDkgQEA5KAEAAAEAQAPgAAAVYABAOSAAADkoBIAAAQCAA+AAAAAgAIA5KABAOSABQAAAwEAB4ACAOSABgAAoAUAAAMBAAiAAAD/gAAA/4ABAAACAgAHgAAA/4AFAAADAAAPgAEA5IACAOSAAQAAAgAID4AAAOSA//8AAA==";

        public static readonly string Ripple = "AAL///7/TABDVEFCHAAAAAMBAAAAAv//BgAAABwAAAAAAQAA/AAAAJQAAAACAAIAAQAKAKAAAAAAAAAAsAAAAAIAAAABAAIAuAAAAAAAAADIAAAAAgADAAEADgCgAAAAAAAAANIAAAACAAQAAQASAKAAAAAAAAAA2AAAAAIAAQABAAYAoAAAAAAAAADdAAAAAwAAAAEAAgDsAAAAAAAAAEFtcGxpdHVkZQCrqwAAAwABAAEAAQAAAAAAAABDZW50ZXIAqwEAAwABAAIAAQAAAAAAAABGcmVxdWVuY3kAU3BlZWQAVGltZQBpbXBsaWNpdElucHV0AKsEAAwAAQABAAEAAAAAAAAAcHNfMl8wAE1pY3Jvc29mdCAoUikgSExTTCBTaGFkZXIgQ29tcGlsZXIgMTAuMQCrUQAABQUAD6AAAAAAF7fROJqZGb4AAIA/UQAABQYAD6BVVdVAAACAP4P5Ij4AAAA/UQAABQcAD6DbD8lA2w9JwM3MzD4AAAAAUQAABQgAD6ABDdC1YQu2t6uqKjuJiIg5UQAABQkAD6Crqqq8AAAAvgAAgD8AAAA/HwAAAgAAAIAAAAOwHwAAAgAAAJAACA+gAgAAAwAAA4AAAOSwAADkoVoAAAQAAASAAADkgAAA5IAFAACgBwAAAgAABIAAAKqABgAAAgAABIAAAKqAAgAAAwAACIAAAKqABQBVoAEAAAIBAAiAAQAAoAQAAAQAAASAAQD/gAQAAKEAAKqABgAAAgAACIAAAP+ABQAAAwAAA4AAAP+AAADkgAUAAAMAAAiAAACqgAMAAKAEAAAEAAAIgAAA/4AGAKqgBgD/oBMAAAIAAAiAAAD/gAQAAAQAAAiAAAD/gAcAAKAHAFWgJQAABAIAAoAAAP+ACADkoAkA5KAFAAADAAAIgAIAVYACAACgBAAABAEAAYAAAKqABgAAoAYAVaACAAADAQACgAEA/4EFAP+gBQAAAwEAAYABAACAAQBVgAUAAAMAAAiAAAD/gAEAAIAEAAAEAAADgAAA5IAAAP+AAADksEIAAAMBAA+AAADkgAAI5KBCAAADAgAPgAAA5LAACOSgBAAABAEAB4AAAP+ABwCqoAEA5IACAAADAAABgAAAqoEFAKqgWAAABAAAAYAAAACABQAAoQUA/6FYAAAEAAABgAAAqoAFAACgAAAAgFgAAAQAAA+AAAAAgAIA5IABAOSAAQAAAgAID4AAAOSA//8AAA==";
    }

    public class AcrylicEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static AcrylicEffect()
        {
            string tempPath = System.IO.Path.Combine(AhkWpfEngine.GetCacheDir(), "AhkAcrylicEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Acrylic);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public AcrylicEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(TintColorProperty);
            UpdateShaderValue(NoiseAmountProperty);
            UpdateShaderValue(BlurRadiusProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(AcrylicEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty TintColorProperty = DependencyProperty.Register("TintColor", typeof(Color), typeof(AcrylicEffect), new PropertyMetadata(Color.FromArgb(50, 255, 255, 255), PixelShaderConstantCallback(0)));
        public Color TintColor
        {
            get { return (Color)GetValue(TintColorProperty); }
            set { SetValue(TintColorProperty, value); }
        }

        public static readonly DependencyProperty NoiseAmountProperty = DependencyProperty.Register("NoiseAmount", typeof(double), typeof(AcrylicEffect), new PropertyMetadata(0.03, PixelShaderConstantCallback(1)));
        public double NoiseAmount
        {
            get { return (double)GetValue(NoiseAmountProperty); }
            set { SetValue(NoiseAmountProperty, value); }
        }

        public static readonly DependencyProperty BlurRadiusProperty = DependencyProperty.Register("BlurRadius", typeof(double), typeof(AcrylicEffect), new PropertyMetadata(0.01, PixelShaderConstantCallback(2)));
        public double BlurRadius
        {
            get { return (double)GetValue(BlurRadiusProperty); }
            set { SetValue(BlurRadiusProperty, value); }
        }
    }

    public class GlowEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static GlowEffect()
        {
            string tempPath = System.IO.Path.Combine(AhkWpfEngine.GetCacheDir(), "AhkGlowEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Glow);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public GlowEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(GlowColorProperty);
            UpdateShaderValue(GlowThicknessProperty);
            UpdateShaderValue(PulseSpeedProperty);
            UpdateShaderValue(TimeProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(GlowEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty GlowColorProperty = DependencyProperty.Register("GlowColor", typeof(Color), typeof(GlowEffect), new PropertyMetadata(Color.FromRgb(0, 242, 254), PixelShaderConstantCallback(0)));
        public Color GlowColor
        {
            get { return (Color)GetValue(GlowColorProperty); }
            set { SetValue(GlowColorProperty, value); }
        }

        public static readonly DependencyProperty GlowThicknessProperty = DependencyProperty.Register("GlowThickness", typeof(double), typeof(GlowEffect), new PropertyMetadata(0.005, PixelShaderConstantCallback(1)));
        public double GlowThickness
        {
            get { return (double)GetValue(GlowThicknessProperty); }
            set { SetValue(GlowThicknessProperty, value); }
        }

        public static readonly DependencyProperty PulseSpeedProperty = DependencyProperty.Register("PulseSpeed", typeof(double), typeof(GlowEffect), new PropertyMetadata(2.0, PixelShaderConstantCallback(2)));
        public double PulseSpeed
        {
            get { return (double)GetValue(PulseSpeedProperty); }
            set { SetValue(PulseSpeedProperty, value); }
        }

        public static readonly DependencyProperty TimeProperty = DependencyProperty.Register("Time", typeof(double), typeof(GlowEffect), new PropertyMetadata(0.0, PixelShaderConstantCallback(3)));
        public double Time
        {
            get { return (double)GetValue(TimeProperty); }
            set { SetValue(TimeProperty, value); }
        }
    }

    public class RippleEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static RippleEffect()
        {
            string tempPath = System.IO.Path.Combine(AhkWpfEngine.GetCacheDir(), "AhkRippleEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Ripple);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public RippleEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(CenterProperty);
            UpdateShaderValue(TimeProperty);
            UpdateShaderValue(AmplitudeProperty);
            UpdateShaderValue(FrequencyProperty);
            UpdateShaderValue(SpeedProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(RippleEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty CenterProperty = DependencyProperty.Register("Center", typeof(Point), typeof(RippleEffect), new PropertyMetadata(new Point(0.5, 0.5), PixelShaderConstantCallback(0)));
        public Point Center
        {
            get { return (Point)GetValue(CenterProperty); }
            set { SetValue(CenterProperty, value); }
        }

        public static readonly DependencyProperty TimeProperty = DependencyProperty.Register("Time", typeof(double), typeof(RippleEffect), new PropertyMetadata(0.0, PixelShaderConstantCallback(1)));
        public double Time
        {
            get { return (double)GetValue(TimeProperty); }
            set { SetValue(TimeProperty, value); }
        }

        public static readonly DependencyProperty AmplitudeProperty = DependencyProperty.Register("Amplitude", typeof(double), typeof(RippleEffect), new PropertyMetadata(0.03, PixelShaderConstantCallback(2)));
        public double Amplitude
        {
            get { return (double)GetValue(AmplitudeProperty); }
            set { SetValue(AmplitudeProperty, value); }
        }

        public static readonly DependencyProperty FrequencyProperty = DependencyProperty.Register("Frequency", typeof(double), typeof(RippleEffect), new PropertyMetadata(30.0, PixelShaderConstantCallback(3)));
        public double Frequency
        {
            get { return (double)GetValue(FrequencyProperty); }
            set { SetValue(FrequencyProperty, value); }
        }

        public static readonly DependencyProperty SpeedProperty = DependencyProperty.Register("Speed", typeof(double), typeof(RippleEffect), new PropertyMetadata(1.2, PixelShaderConstantCallback(4)));
        public double Speed
        {
            get { return (double)GetValue(SpeedProperty); }
            set { SetValue(SpeedProperty, value); }
        }
    }

    public class CyberpunkGradientEffect : System.Windows.Media.Effects.ShaderEffect
    {
        private static readonly System.Windows.Media.Effects.PixelShader _pixelShader = new System.Windows.Media.Effects.PixelShader();

        static CyberpunkGradientEffect()
        {
            string tempPath = System.IO.Path.Combine(AhkWpfEngine.GetCacheDir(), "AhkCyberpunkGradientEffect.ps");
            try
            {
                if (!System.IO.File.Exists(tempPath))
                {
                    byte[] bytecode = Convert.FromBase64String(Bytecodes.Gradient);
                    System.IO.File.WriteAllBytes(tempPath, bytecode);
                }
                _pixelShader.UriSource = new Uri(tempPath);
            }
            catch { }
        }

        public CyberpunkGradientEffect()
        {
            this.PixelShader = _pixelShader;
            UpdateShaderValue(InputProperty);
            UpdateShaderValue(Color1Property);
            UpdateShaderValue(Color2Property);
            UpdateShaderValue(Color3Property);
            UpdateShaderValue(AngleProperty);
            UpdateShaderValue(SpeedProperty);
            UpdateShaderValue(TimeProperty);
            UpdateShaderValue(BrightnessProperty);
        }

        public static readonly DependencyProperty InputProperty = System.Windows.Media.Effects.ShaderEffect.RegisterPixelShaderSamplerProperty("Input", typeof(CyberpunkGradientEffect), 0);
        public Brush Input
        {
            get { return (Brush)GetValue(InputProperty); }
            set { SetValue(InputProperty, value); }
        }

        public static readonly DependencyProperty Color1Property = DependencyProperty.Register("Color1", typeof(Color), typeof(CyberpunkGradientEffect), new PropertyMetadata(Color.FromRgb(0, 242, 254), PixelShaderConstantCallback(0)));
        public Color Color1
        {
            get { return (Color)GetValue(Color1Property); }
            set { SetValue(Color1Property, value); }
        }

        public static readonly DependencyProperty Color2Property = DependencyProperty.Register("Color2", typeof(Color), typeof(CyberpunkGradientEffect), new PropertyMetadata(Color.FromRgb(253, 0, 140), PixelShaderConstantCallback(1)));
        public Color Color2
        {
            get { return (Color)GetValue(Color2Property); }
            set { SetValue(Color2Property, value); }
        }

        public static readonly DependencyProperty Color3Property = DependencyProperty.Register("Color3", typeof(Color), typeof(CyberpunkGradientEffect), new PropertyMetadata(Color.FromRgb(141, 0, 255), PixelShaderConstantCallback(2)));
        public Color Color3
        {
            get { return (Color)GetValue(Color3Property); }
            set { SetValue(Color3Property, value); }
        }

        public static readonly DependencyProperty AngleProperty = DependencyProperty.Register("Angle", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(45.0, PixelShaderConstantCallback(3)));
        public double Angle
        {
            get { return (double)GetValue(AngleProperty); }
            set { SetValue(AngleProperty, value); }
        }

        public static readonly DependencyProperty SpeedProperty = DependencyProperty.Register("Speed", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(0.5, PixelShaderConstantCallback(4)));
        public double Speed
        {
            get { return (double)GetValue(SpeedProperty); }
            set { SetValue(SpeedProperty, value); }
        }

        public static readonly DependencyProperty TimeProperty = DependencyProperty.Register("Time", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(0.0, PixelShaderConstantCallback(5)));
        public double Time
        {
            get { return (double)GetValue(TimeProperty); }
            set { SetValue(TimeProperty, value); }
        }

        public static readonly DependencyProperty BrightnessProperty = DependencyProperty.Register("Brightness", typeof(double), typeof(CyberpunkGradientEffect), new PropertyMetadata(1.0, PixelShaderConstantCallback(6)));
        public double Brightness
        {
            get { return (double)GetValue(BrightnessProperty); }
            set { SetValue(BrightnessProperty, value); }
        }
    }
}
#endif
