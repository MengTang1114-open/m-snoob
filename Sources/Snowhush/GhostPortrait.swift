import AppKit
import Metal
import MetalKit
import simd

/// How the desktop ghost is feeling. The snow ghost and the icon use the same drawing.
enum GhostMood: Float {
    case dozing = 0
    case timing = 1
    case anxious = 2
}

/// One small ghost, drawn with the same sheet, head, skirt and eyes as the ghost in the snow.
/// The snow sprite lives inside the big runtime shader, so this is that ghost function copied
/// out with the same distances. A portrait has no drift mesh, so a short heap is drawn under the hem.
enum GhostPortrait {
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Portrait {
        float2 viewSize;
        float time;
        float mood;
        float bodySize;
        float bold;
        float nudge;
        float4 light;
        float4 shadowTint;
        float4 rim;
    };

    struct PortraitOut {
        float4 position [[position]];
    };

    constant float3 candle = float3(1.0, 0.62, 0.26);

    static float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    vertex PortraitOut portraitVertex(uint vid [[vertex_id]]) {
        float2 corner = float2(float(vid & 1), float(vid >> 1));
        PortraitOut out;
        out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    fragment float4 portraitFragment(PortraitOut in [[stage_in]], constant Portrait &u [[buffer(0)]]) {
        float2 frag = in.position.xy;
        float2 centered = float2(frag.x - u.viewSize.x * 0.5, u.viewSize.y * 0.5 - frag.y);
        float span = min(u.viewSize.x, u.viewSize.y);
        float2 p = centered / max(span, 1.0);
        // Move the ghost up so the heap sits inside the view, above the caption.
        // `nudge` drops it for the icon, where the skirt should meet the snow bank.
        p.y -= 0.08 - u.nudge;
        float t = u.time;
        float anxious = step(1.5, u.mood);
        float awake = step(0.5, u.mood);
        p.y -= (0.15 + awake * 0.85) * 0.018 * sin(t * (anxious > 0.5 ? 2.4 : 1.2));
        p.x -= anxious * 0.012 * sin(t * 57.0);

        float ground = -0.035;
        float form = 1.0;
        float shaped = 1.0;
        float heap = 0.3;
        float2 q = float2(p.x - sin(t * 1.2 + p.y * 3.5) * 0.02 * (0.22 - p.y) * shaped, p.y);
        float side = 0.17 + pow(max(0.22 - q.y, 0.0), 1.3) * 0.35;
        float sheet = q.y > 0.22 ? 0.17 - length(q - float2(0.0, 0.22)) : side - abs(q.x);
        float skirt = ground + 0.07 * smoothstep(0.45, 0.0, abs(p.x)) - p.y;
        float blend = max(0.05 - abs(sheet - skirt), 0.0) / 0.05;
        float formed = max(sheet, skirt) + blend * blend * 0.05 * 0.25;

        float cover = 0.0;
        for (float hand = -1.0; hand <= 1.0; hand += 2.0) {
            float angle = -1.35;
            float2 joint = float2(hand * 0.17, 0.1);
            for (int k = 1; k <= 3; k++) {
                float2 next = float2(hand * 0.17, 0.1) + float2(hand * cos(angle), sin(angle)) * (0.057 * float(k));
                float2 bone = next - joint;
                float along = saturate(dot(q - joint, bone) / max(dot(bone, bone), 1e-5));
                float radius = 0.045 * 0.4 * (1.0 - 0.08 * float(k - 1) - 0.08 * along);
                float paw = radius - length(q - joint - bone * along);
                float join = max(0.03 - abs(formed - paw), 0.0) / 0.03;
                formed = max(formed, paw) + join * join * 0.03 * 0.25;
                joint = next;
            }
        }

        float inside = mix(ground + heap * smoothstep(0.34, 0.0, abs(p.x)) - p.y, formed, shaped);
        float under = ground - p.y;
        float sunk = (1.0 - smoothstep(0.05, 0.11, under)) * smoothstep(0.45, 0.25, abs(p.x));
        float edge = u.bold > 0.5 ? 0.05 : 0.02;
        float a = smoothstep(0.0, edge, inside) * max(1.0 - smoothstep(-0.015, 0.0, under), sunk);

        float depth = max(inside, 0.0) * u.bodySize;
        float2 slope = float2(dfdx(inside), -dfdy(inside));
        float lit = length(slope) > 0.0 ? dot(normalize(-slope), normalize(float2(-0.5, 1.0))) : 1.0;
        float folds = (0.5 + 0.5 * sin(q.x / side * 7.5 + sin(q.y * 5.0 + t * 0.9) * 0.8)) * smoothstep(0.18, -0.2, q.y) * shaped;
        float shade = (1.0 - exp(-depth / 30.0)) * 0.32 + (1.0 - lit) * 0.6 * exp(-depth / 5.0) + folds * 0.18;
        float3 shadow = mix(float3(0.72, 0.78, 0.88), u.shadowTint.rgb, u.shadowTint.a);
        float3 surface = mix(float3(0.925, 0.94, 0.965), min(u.shadowTint.rgb * 1.18, float3(1.0)), u.shadowTint.a * 0.2);
        float3 color = mix(surface, shadow, saturate(shade));
        color = mix(color, float3(0.975, 0.982, 0.995), exp(-depth * 0.9) * 0.6);
        float below = max(under, 0.0) * u.bodySize;
        float3 drift = mix(surface, shadow, saturate((1.0 - exp(-below / 30.0)) * 0.32 + 0.064 * exp(-below / 5.0)));
        color = mix(color, mix(drift, float3(0.975, 0.982, 0.995), exp(-below * 0.9) * 0.6), smoothstep(1.0, 4.0, below));
        color += (hash(float2(3.0, 5.0)) - 0.5) * 0.02;
        color *= u.light.rgb;
        color = mix(color, u.rim.rgb, u.rim.a * exp(-depth / 2.5));
        color = mix(color, candle, 0.0);

        float blink = awake < 0.5 ? 1.0 : anxious > 0.5 ? 0.0 : step(fract(t * 0.29 + 7.0), 0.035);
        float eyeScale = anxious > 0.5 ? 1.35 : 1.0;
        float2 eye = float2(0.03 * eyeScale, 0.042 * eyeScale * (1.0 - 0.85 * blink));
        float eyes = 0.0;
        for (float s = -1.0; s <= 1.0; s += 2.0) {
            float2 e = q - float2(s * 0.065, 0.24);
            eyes = max(eyes, 1.0 - smoothstep(0.75, 1.0, length(e / eye)));
        }
        eyes *= (1.0 - cover);
        color = mix(color, float3(0.06, 0.06, 0.09), eyes * smoothstep(0.2, 0.85, form));

        // Bounded heap. It covers the sprite's straight fade-out, which the real drift hides.
        float2 heapP = float2(p.x / 0.46, (p.y - (ground - 0.02)) / 0.10);
        float pileA = smoothstep(1.15, 0.35, dot(heapP, heapP));
        float front = smoothstep(ground + 0.06, ground - 0.01, p.y);
        float3 pileColor = mix(surface, shadow, 0.38) * u.light.rgb;
        float hem = pileA * front;
        float showPile = max(front, 1.0 - a);
        float3 prem = color * a * (1.0 - hem) + pileColor * pileA * showPile;
        float outA = saturate(a * (1.0 - hem) + pileA * showPile);
        if (outA < 0.004) discard_fragment();
        return float4(prem, outA);
    }
    """
}

/// Compiles the portrait once and draws it into a view or an offscreen texture.
final class GhostPortraitRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: GhostPortrait.shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "portraitVertex"),
                  let fragment = library.makeFunction(name: "portraitFragment") else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("雪噗噗: portrait shader failed: \(error)")
            return nil
        }
        self.device = device
        self.queue = queue
    }

    func draw(in view: MTKView, mood: GhostMood, time: Float) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(encoder, size: drawable.texture.width == 0 ? view.drawableSize : CGSize(width: drawable.texture.width, height: drawable.texture.height), mood: mood, time: time, bold: false)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Transparent BGRA image of the ghost. `bold` thickens the hem for 16-point icons.
    func renderImage(pixels: Int, mood: GhostMood, time: Float, bold: Bool, nudge: Float = 0) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: pixels, height: pixels, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let pass = MTLRenderPassDescriptor()
        guard let texture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer() else { return nil }
        let attachment = pass.colorAttachments[0]!
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        attachment.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encode(encoder, size: CGSize(width: pixels, height: pixels), mood: mood, time: time, bold: bold, nudge: nudge)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let count = pixels * pixels * 4
        var bytes = [UInt8](repeating: 0, count: count)
        texture.getBytes(&bytes, bytesPerRow: pixels * 4, from: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0)
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private func encode(_ encoder: MTLRenderCommandEncoder, size: CGSize, mood: GhostMood, time: Float, bold: Bool, nudge: Float = 0) {
        var uniforms = PortraitUniforms(
            viewSize: SIMD2(Float(size.width), Float(size.height)),
            time: time,
            mood: mood.rawValue,
            bodySize: 68,
            bold: bold ? 1 : 0,
            nudge: nudge,
            light: SIMD4(0.93, 0.95, 1.0, 1),
            shadowTint: SIMD4(0.72, 0.78, 0.88, 0.35),
            rim: SIMD4(0.78, 0.86, 0.98, 0.28)
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PortraitUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

private struct PortraitUniforms {
    var viewSize: SIMD2<Float>
    var time: Float
    var mood: Float
    var bodySize: Float
    var bold: Float
    var nudge: Float
    var light: SIMD4<Float>
    var shadowTint: SIMD4<Float>
    var rim: SIMD4<Float>
}

/// A Retina view that keeps one ghost moving.
final class GhostPortraitView: MTKView, MTKViewDelegate {
    var mood = GhostMood.dozing
    private let portrait: GhostPortraitRenderer?
    private var started = CACurrentMediaTime()

    init(portrait: GhostPortraitRenderer?) {
        self.portrait = portrait
        super.init(frame: .zero, device: portrait == nil ? nil : MTLCreateSystemDefaultDevice())
        wantsLayer = true
        layer?.isOpaque = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        autoResizeDrawable = false
        preferredFramesPerSecond = 30
        delegate = self
        isPaused = portrait == nil
        enableSetNeedsDisplay = portrait == nil
    }

    required init(coder: NSCoder) {
        portrait = nil
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        let scale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if drawableSize != size, size.width > 1, size.height > 1 { drawableSize = size }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        portrait?.draw(in: view, mood: mood, time: Float(CACurrentMediaTime() - started))
    }
}
