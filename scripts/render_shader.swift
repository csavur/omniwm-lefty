// swift scripts/render_shader.swift <style folder> <output folder> [tag ...]
// Compiles shaders/glow.metal with OmniWM 0.8's prelude, renders it in both palettes and
// reports the worst text contrast above the bottom quarter of the bar, where no text sits.
import AppKit
import Metal

let style = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
let roles = ["background", "surface", "elevatedSurface", "foreground", "secondaryForeground", "mutedForeground", "border",
             "accent", "accentForeground", "success", "warning", "error", "focus", "shadow", "scrim", "badge"]
func palette(_ mode: String) throws -> [String: SIMD4<Float>] {
    var section = "", result: [String: SIMD4<Float>] = [:]
    for line in try String(contentsOf: style.appending(path: "themes/lefty.toml"), encoding: .utf8).split(separator: "\n") {
        if line.hasPrefix("[") { section = String(line.dropFirst().dropLast()); continue }
        let parts = line.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        guard section == mode, parts.count == 2 else { continue }
        let hex = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"#"))
        let v = UInt32(hex.prefix(6), radix: 16)!
        result[parts[0]] = SIMD4(Float(v >> 16) / 255, Float(v >> 8 & 255) / 255, Float(v & 255) / 255, 1)
    }
    return result
}
let body = try String(contentsOf: style.appending(path: "shaders/glow.metal"), encoding: .utf8)
let source = """
#include <metal_stdlib>
using namespace metal;
struct OmniShader { float2 size; float scale; float time; float4 values; float4 colors[40]; float progress; float2 anchor; float4 content; float audio[60]; };
\(roles.enumerated().map { "constant int omni_\($1) = \($0);" }.joined(separator: "\n"))
struct OmniVertex { float4 position [[position]]; float2 uv; };
vertex OmniVertex omni_vertex(uint id [[vertex_id]]) { float2 uv = float2((id << 1) & 2, id & 2); OmniVertex o; o.position = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1); o.uv = uv; return o; }
float omni_noise(float2 point) {
    float2 cell = floor(point); float2 local = fract(point); local = local * local * (3.0 - 2.0 * local);
    float4 hashes = fract(sin(float4(dot(cell, float2(127.1, 311.7)), dot(cell + float2(1, 0), float2(127.1, 311.7)), dot(cell + float2(0, 1), float2(127.1, 311.7)), dot(cell + 1.0, float2(127.1, 311.7)))) * 43758.5453);
    return mix(mix(hashes.x, hashes.y, local.x), mix(hashes.z, hashes.w, local.x), local.y);
}
\(body)
fragment half4 omni_fragment(OmniVertex in [[stage_in]], constant OmniShader& shader [[buffer(0)]]) { float4 c = shade(in.uv, shader); return half4(float4(c.rgb * c.a, c.a)); }
"""
let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
let library = try device.makeLibrary(source: source, options: nil)
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "omni_vertex")
descriptor.fragmentFunction = library.makeFunction(name: "omni_fragment")
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

func render(_ w: Int, _ h: Int, scale: Float, time: Float, values: SIMD4<Float>, colors: [String: SIMD4<Float>]) -> [UInt8] {
    // layout: size 0, scale 8, time 12, values 16, colors 32..672, progress 672, anchor 680, content 688, audio 704..944
    var buffer = [Float](repeating: 0, count: 944 / 4)
    buffer[0] = Float(w) / scale; buffer[1] = Float(h) / scale; buffer[2] = scale; buffer[3] = time
    for i in 0 ..< 4 { buffer[4 + i] = values[i] }
    for (i, role) in roles.enumerated() { for k in 0 ..< 4 { buffer[8 + i * 4 + k] = colors[role]![k] } }
    buffer[168] = 1
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
    td.usage = [.renderTarget]; td.storageMode = .shared
    let texture = device.makeTexture(descriptor: td)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture; pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
    let commands = queue.makeCommandBuffer()!, encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(pipeline); encoder.setFragmentBytes(buffer, length: 944, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
    commands.commit(); commands.waitUntilCompleted()
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    texture.getBytes(&pixels, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    return pixels
}
func luminance(_ r: Float, _ g: Float, _ b: Float) -> Float {
    func f(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : powf((x + 0.055) / 1.055, 2.4) }
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}
func worst(_ pixels: [UInt8], _ color: SIMD4<Float>) -> Float {
    let text = luminance(color.x, color.y, color.z); var low: Float = 99
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let l = luminance(Float(pixels[i + 2]) / 255, Float(pixels[i + 1]) / 255, Float(pixels[i]) / 255)
        low = min(low, (max(l, text) + 0.05) / (min(l, text) + 0.05))
    }
    return low
}
func save(_ pixels: [UInt8], _ w: Int, _ h: Int, _ name: String) throws {
    var rgba = pixels
    for i in stride(from: 0, to: rgba.count, by: 4) { rgba.swapAt(i, i + 2) }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
    rgba.withUnsafeBytes { rep.bitmapData!.update(from: $0.bindMemory(to: UInt8.self).baseAddress!, count: rgba.count) }
    try rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
}
let bar = SIMD4<Float>(0.6, 1, 1.2, 0.4), panel = SIMD4<Float>(0.35, 0.7, 1.4, 0.35)
for mode in ["dark", "light"] {
    let colors = try palette(mode)
    var off = bar; off.x = 0
    var still = bar; still.y = 0
    precondition(render(640, 80, scale: 2, time: 0, values: off, colors: colors) == render(640, 80, scale: 2, time: 9, values: off, colors: colors))
    precondition(render(640, 80, scale: 2, time: 0, values: still, colors: colors) == render(640, 80, scale: 2, time: 9, values: still, colors: colors))
    precondition(render(640, 80, scale: 2, time: 0, values: bar, colors: colors) != render(640, 80, scale: 2, time: 9, values: bar, colors: colors))
    for (name, w, h, values) in [("bar", 2400, 80, bar), ("vertical", 80, 1200, bar), ("panel", 696, 900, panel)] {
        var lows: [Float] = [99, 99]
        for step in 0 ..< 12 {
            let p = render(w, h, scale: 2, time: Float(step) * 2.7, values: values, colors: colors)
            let text = Array(p.prefix(w * (h - min(h, 120) / 4) * 4))
            lows[0] = min(lows[0], worst(text, colors["foreground"]!)); lows[1] = min(lows[1], worst(text, colors["secondaryForeground"]!))
            if step == 4 { try save(p, w, h, "\(name)-\(mode).png") }
        }
        print(mode, name, "foreground", lows[0], "secondary", lows[1], lows.min()! >= 4.5 ? "ok" : "TOO LOW")
    }
}
