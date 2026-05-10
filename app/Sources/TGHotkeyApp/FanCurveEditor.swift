import SwiftUI

/// 可拖拽折线图：横轴 20-90°C（5°C 一格），纵轴 0-100%（5% 一格） + 底部「Stop」档。
/// 拖动点即调整曲线，按 5°C / 5% 自动吸附。点击 +/- 加减点，右键点删除。
/// 0% = 风扇硬件最低 RPM（约 2317）；Stop = 不写规则，让系统自动控制（可完全停转）。
struct FanCurveEditor: View {
    @Binding var curve: [CurvePoint]

    /// percent < 0 表示 "Stop"（不生成 TG Pro 规则），lua 端会过滤
    static let stopSentinel: Int = -10

    private let tempLow: Double = 20
    private let tempHigh: Double = 90
    private let tempStep: Double = 5
    private let percentLow: Double = 0
    private let percentHigh: Double = 100
    private let percentStep: Double = 5
    /// "Stop" 档用一格画在 0% 下方
    private let stopBandHeight: Int = -10

    private let leftPad: CGFloat = 38
    private let rightPad: CGFloat = 12
    private let topPad: CGFloat = 12
    private let bottomPad: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(
                x: leftPad,
                y: topPad,
                width: max(0, geo.size.width - leftPad - rightPad),
                height: max(0, geo.size.height - topPad - bottomPad)
            )
            ZStack {
                background(in: plot)
                gridLines(in: plot)
                axisLabels(in: plot)
                lineConnecting(points: sortedPoints, in: plot)
                pointHandles(in: plot)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 260)
        .padding(.bottom, 4)
    }

    // ---- 子视图 ----

    private func background(in plot: CGRect) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.06))
            .frame(width: plot.width, height: plot.height)
            .position(x: plot.midX, y: plot.midY)
    }

    @ViewBuilder
    private func gridLines(in plot: CGRect) -> some View {
        // 细网格：5°C / 5% 一格
        Path { path in
            var t = tempLow
            while t <= tempHigh + 0.0001 {
                let x = xPos(t, in: plot)
                path.move(to: CGPoint(x: x, y: plot.minY))
                path.addLine(to: CGPoint(x: x, y: plot.maxY))
                t += tempStep
            }
            var p = percentLow
            while p <= percentHigh + 0.0001 {
                let y = yPos(p, in: plot)
                path.move(to: CGPoint(x: plot.minX, y: y))
                path.addLine(to: CGPoint(x: plot.maxX, y: y))
                p += percentStep
            }
        }
        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        // 主网格：每 10°C / 25% 加深
        Path { path in
            var t = tempLow
            while t <= tempHigh + 0.0001 {
                let x = xPos(t, in: plot)
                path.move(to: CGPoint(x: x, y: plot.minY))
                path.addLine(to: CGPoint(x: x, y: plot.maxY))
                t += 10
            }
            for p in [0, 25, 50, 75, 100] {
                let y = yPos(Double(p), in: plot)
                path.move(to: CGPoint(x: plot.minX, y: y))
                path.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
        }
        .stroke(Color.gray.opacity(0.35), lineWidth: 0.6)
    }

    @ViewBuilder
    private func axisLabels(in plot: CGRect) -> some View {
        // X 轴温度刻度（每 5°C 一标）
        ForEach(Array(stride(from: tempLow, through: tempHigh, by: tempStep)), id: \.self) { t in
            Text("\(Int(t))")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .position(x: xPos(t, in: plot), y: plot.maxY + 10)
        }
        // Y 轴百分比刻度（每 25% 一标）
        ForEach([0, 25, 50, 75, 100], id: \.self) { p in
            Text("\(p)%")
                .font(.caption2)
                .foregroundColor(.secondary)
                .position(x: leftPad - 18, y: yPos(Double(p), in: plot))
        }
        // Y 轴底部 "Stop" 档标签
        Text("Stop")
            .font(.caption2.bold())
            .foregroundColor(.orange)
            .position(x: leftPad - 18, y: yPos(Double(stopBandHeight), in: plot))
        // 0% 那条线加深一点，明确划开 Stop 区
        Path { path in
            let y = yPos(0, in: plot)
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
        }.stroke(Color.orange.opacity(0.4), lineWidth: 1)
    }

    private func lineConnecting(points: [CurvePoint], in plot: CGRect) -> some View {
        Path { path in
            guard !points.isEmpty else { return }
            let first = points[0]
            // 起点：从左边界水平延伸到第一个点（小于 first.temp 时仍按 first.percent）
            path.move(to: CGPoint(x: plot.minX, y: yPos(Double(first.percent), in: plot)))
            path.addLine(to: CGPoint(x: xPos(first.temperatureLimit, in: plot),
                                     y: yPos(Double(first.percent), in: plot)))
            for p in points.dropFirst() {
                path.addLine(to: CGPoint(x: xPos(p.temperatureLimit, in: plot),
                                         y: yPos(Double(p.percent), in: plot)))
            }
            // 末端：从最后一个点水平延伸到右边界
            if let last = points.last {
                path.addLine(to: CGPoint(x: plot.maxX, y: yPos(Double(last.percent), in: plot)))
            }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    @ViewBuilder
    private func pointHandles(in plot: CGRect) -> some View {
        ForEach(curve.indices, id: \.self) { i in
            let cp = curve[i]
            let isStop = cp.percent < 0
            let pos = CGPoint(x: xPos(cp.temperatureLimit, in: plot),
                              y: yPos(Double(cp.percent), in: plot))
            Circle()
                .fill(isStop ? Color.orange : Color.accentColor)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle().stroke(Color.white, lineWidth: 2)
                )
                .position(pos)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let newT = snapTemp(temp(at: v.location.x, in: plot))
                            let newP = snapPercent(percent(at: v.location.y, in: plot))
                            curve[i].temperatureLimit = newT
                            curve[i].percent = Int(newP)
                        }
                        .onEnded { _ in
                            curve.sort { $0.temperatureLimit < $1.temperatureLimit }
                        }
                )
                .contextMenu {
                    Button(role: .destructive) {
                        if curve.count > 1 { curve.remove(at: i) }
                    } label: { Label("删除这个点", systemImage: "trash") }
                }
                // 旁边显示当前值
                .overlay(
                    Text(isStop ? "\(Int(cp.temperatureLimit))° Stop" : "\(Int(cp.temperatureLimit))° \(cp.percent)%")
                        .font(.caption2.monospaced())
                        .foregroundColor(isStop ? .orange : .primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: 0, y: -18)
                        .position(pos)
                        .allowsHitTesting(false)
                )
        }
    }

    // ---- 几何工具 ----
    private var sortedPoints: [CurvePoint] {
        curve.sorted { $0.temperatureLimit < $1.temperatureLimit }
    }
    private func xPos(_ t: Double, in plot: CGRect) -> CGFloat {
        let f = (t - tempLow) / (tempHigh - tempLow)
        return plot.minX + plot.width * CGFloat(min(max(f, 0), 1))
    }
    /// Y 轴范围扩展：`stopBandHeight` (-10) 到 `percentHigh` (100)。0% 之下额外一格放 "Stop"。
    private var yRangeMin: Double { Double(stopBandHeight) }
    private var yRangeMax: Double { percentHigh }
    private func yPos(_ p: Double, in plot: CGRect) -> CGFloat {
        let pClamped = max(yRangeMin, min(yRangeMax, p))
        let f = (pClamped - yRangeMin) / (yRangeMax - yRangeMin)
        return plot.maxY - plot.height * CGFloat(f)
    }
    private func temp(at x: CGFloat, in plot: CGRect) -> Double {
        let f = Double((x - plot.minX) / max(plot.width, 1))
        return tempLow + f * (tempHigh - tempLow)
    }
    private func percent(at y: CGFloat, in plot: CGRect) -> Double {
        let f = Double((plot.maxY - y) / max(plot.height, 1))
        return yRangeMin + f * (yRangeMax - yRangeMin)
    }
    private func snapTemp(_ t: Double) -> Double {
        let s = (t / tempStep).rounded() * tempStep
        return min(tempHigh, max(tempLow, s))
    }
    /// 拖到 0% 以下任意位置都吸到 Stop（停止）档
    private func snapPercent(_ p: Double) -> Double {
        if p < 0 { return Double(Self.stopSentinel) }
        let s = (p / percentStep).rounded() * percentStep
        return min(percentHigh, max(percentLow, s))
    }
}
