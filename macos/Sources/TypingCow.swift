import AppKit

final class TypingCowView: NSView, WorkMascotView {
    private static let halo = NSColor.fromHex("#5069BEA6")
    private static let cream = NSColor.fromHex("#FFF3DB")
    private static let cocoa = NSColor.fromHex("#604843")
    private static let blush = NSColor.fromHex("#F6B6AD")
    private static let gold = NSColor.fromHex("#FFD98B")
    private static let laptop = NSColor.fromHex("#38675D")
    private static let mint = NSColor.fromHex("#A2E3CD")

    private var typingStart: TimeInterval?
    private var working = false
    private var frameIndex = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityLabel("敲键盘的小牛")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func showWork(working isWorking: Bool, animate: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if animate {
            if typingStart == nil {
                typingStart = now
            }
        } else {
            typingStart = nil
        }

        let elapsedMs: Int64
        if let start = typingStart {
            elapsedMs = max(0, Int64((now - start) * 1000.0))
        } else {
            elapsedMs = 0
        }

        let nextFrame = Int((elapsedMs / 90) % 4)
        if working == isWorking && frameIndex == nextFrame {
            return
        }
        working = isWorking
        frameIndex = nextFrame
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: bounds.width / 66.0, y: bounds.height / 66.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let bob: CGFloat = (working && frameIndex % 2 == 1) ? 1.2 : 0
        drawEllipse(ctx, fill: Self.halo, stroke: nil, lineWidth: 0, x: 33, y: 33, rx: 32, ry: 32)

        ctx.saveGState()
        ctx.translateBy(x: 0, y: bob)
        drawEllipse(ctx, fill: Self.gold, stroke: Self.cocoa, lineWidth: 1.4, x: 23, y: 13, rx: 4, ry: 8)
        drawEllipse(ctx, fill: Self.gold, stroke: Self.cocoa, lineWidth: 1.4, x: 43, y: 13, rx: 4, ry: 8)
        drawEllipse(ctx, fill: Self.cream, stroke: Self.cocoa, lineWidth: 1.4, x: 15, y: 22, rx: 8, ry: 4.5)
        drawEllipse(ctx, fill: Self.cream, stroke: Self.cocoa, lineWidth: 1.4, x: 51, y: 22, rx: 8, ry: 4.5)
        drawEllipse(ctx, fill: Self.blush, stroke: nil, lineWidth: 0, x: 14, y: 22, rx: 4.5, ry: 2)
        drawEllipse(ctx, fill: Self.blush, stroke: nil, lineWidth: 0, x: 52, y: 22, rx: 4.5, ry: 2)
        drawEllipse(ctx, fill: Self.cream, stroke: Self.cocoa, lineWidth: 1.4, x: 33, y: 28, rx: 18, ry: 15.5)
        drawEllipse(ctx, fill: Self.cocoa, stroke: nil, lineWidth: 0, x: 41, y: 18, rx: 5, ry: 3)
        drawEllipse(ctx, fill: Self.cocoa, stroke: nil, lineWidth: 0, x: 24, y: 27, rx: 1.5, ry: 2)
        drawEllipse(ctx, fill: Self.cocoa, stroke: nil, lineWidth: 0, x: 42, y: 27, rx: 1.5, ry: 2)
        drawEllipse(ctx, fill: Self.blush, stroke: nil, lineWidth: 0, x: 20, y: 32, rx: 2.5, ry: 1.3)
        drawEllipse(ctx, fill: Self.blush, stroke: nil, lineWidth: 0, x: 46, y: 32, rx: 2.5, ry: 1.3)
        drawEllipse(ctx, fill: Self.blush, stroke: Self.cocoa, lineWidth: 1.4, x: 33, y: 34.5, rx: 9, ry: 5.2)
        drawEllipse(ctx, fill: Self.cocoa, stroke: nil, lineWidth: 0, x: 30, y: 33.5, rx: 1, ry: 0.9)
        drawEllipse(ctx, fill: Self.cocoa, stroke: nil, lineWidth: 0, x: 36, y: 33.5, rx: 1, ry: 0.9)

        ctx.setStrokeColor(Self.cocoa.cgColor)
        ctx.setLineWidth(1.2)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 30, y: 36.5))
        ctx.addQuadCurve(to: CGPoint(x: 36, y: 36.5), control: CGPoint(x: 33, y: 39))
        ctx.strokePath()
        ctx.restoreGState()

        let leftHoof: CGFloat = (working && frameIndex % 2 == 1) ? 48 : 51
        let rightHoof: CGFloat = (working && frameIndex % 2 == 0) ? 48 : 51
        drawEllipse(ctx, fill: Self.cream, stroke: Self.cocoa, lineWidth: 1.4, x: 15, y: leftHoof, rx: 5, ry: 4)
        drawEllipse(ctx, fill: Self.cream, stroke: Self.cocoa, lineWidth: 1.4, x: 51, y: rightHoof, rx: 5, ry: 4)
        drawRoundedRect(ctx, fill: Self.laptop, stroke: Self.cocoa, lineWidth: 1.4,
                        rect: CGRect(x: 17, y: 43, width: 32, height: 17), radius: 3)
        drawRoundedRect(ctx, fill: Self.mint, stroke: Self.cocoa, lineWidth: 1.4,
                        rect: CGRect(x: 13, y: 58, width: 40, height: 4), radius: 2)
        drawEllipse(ctx, fill: Self.gold, stroke: nil, lineWidth: 0, x: 33, y: 51, rx: 2.3, ry: 2.3)

        if working {
            let x: CGFloat = frameIndex < 2 ? 55 : 10
            ctx.setStrokeColor(Self.gold.cgColor)
            ctx.setLineWidth(1.6)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x - 2, y: 39))
            ctx.addLine(to: CGPoint(x: x + 2, y: 39))
            ctx.move(to: CGPoint(x: x, y: 37))
            ctx.addLine(to: CGPoint(x: x, y: 41))
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    private func drawEllipse(
        _ ctx: CGContext,
        fill: NSColor?,
        stroke: NSColor?,
        lineWidth: CGFloat,
        x: CGFloat,
        y: CGFloat,
        rx: CGFloat,
        ry: CGFloat
    ) {
        let rect = CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)
        if let fill {
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: rect)
        }
        if let stroke {
            ctx.setStrokeColor(stroke.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: rect)
        }
    }

    private func drawRoundedRect(
        _ ctx: CGContext,
        fill: NSColor,
        stroke: NSColor,
        lineWidth: CGFloat,
        rect: CGRect,
        radius: CGFloat
    ) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
    }
}
