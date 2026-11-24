// Views of the Power Flow widget.
// Both sizes draw the energy loop, after the energy monitor of a hybrid car: CHARGER, SYSTEM
// and BATTERY on a ring.
// One cue per state: a lit leg of the ring says that power moves, and where. No arrow, sign
// or state word repeats it. The colour of a leg names its source: green from the charger,
// orange from the battery. The width of a leg follows the watts on it.
// The widget shows no watts: a number is only right for a moment.
// Small: the loop around the charge level. Medium: the loop beside one row per component.

import AppKit
import CoreText
import SwiftUI
import WidgetKit

struct PowerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PowerEntry

    var body: some View {
        PowerContent(
            sample: entry.sample, family: family, frame: entry.frame, batch: entry.batch)
            // macOS drops this background when the desktop dims widgets or the user picks
            // a clear or tinted widget style. The legs still carry their colours then.
            .containerBackground(for: .widget) {
                NetBackground(sample: entry.sample)
            }
    }
}

/// The widget's background: a system fill, washed from the bottom with the colour of the
/// battery's net motion, like the sky of the Weather widget. Green is a net gain, orange a
/// net loss. A battery that holds, or a Mac without one, has no wash. It is the one cue for
/// gain or loss: no word, sign or arrow says it again.
struct NetBackground: View {
    let sample: PowerSample?

    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            if let tint {
                LinearGradient(
                    colors: [tint.opacity(0.42), tint.opacity(0.08)],
                    startPoint: .bottom, endPoint: .top)
            }
        }
    }

    private var tint: Color? {
        switch sample?.motion {
        case .charging: .green
        case .draining: .orange
        default: nil
        }
    }
}

/// The content of the widget in one size. A nil sample is a Mac without a battery.
/// The size is a parameter so that Preview/States.swift can draw it outside WidgetKit.
struct PowerContent: View {
    let sample: PowerSample?
    let family: WidgetFamily
    /// How far the flow animation has run, in steps, and the run it belongs to. See `Flow`.
    var frame = 0.0
    var batch = 0

    var body: some View {
        if let sample {
            Group {
                if family == .systemMedium {
                    MediumView(sample: sample, frame: frame, batch: batch)
                } else {
                    LoopView(sample: sample, showsTime: true, frame: frame, batch: batch)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sample.spokenSummary)
        } else {
            NoBatteryView()
        }
    }
}

// MARK: - Presentation rules

extension PowerSample {
    /// Charge level, e.g. "86%".
    var level: String { "\(min(max(percent, 0), 100))%" }

    /// Time to full or empty, e.g. "1h 20m" or "45 min". Empty when macOS has no estimate.
    var timeLeft: String {
        guard let minutes = minutesLeft else { return "" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// SF Symbol of the power port station. It is a plug for power in and for power out:
    /// the lit leg and its pulses show which way the power moves.
    static let portSymbol = "powerplug.fill"

    /// Power moves through the port station, in or out.
    var portActive: Bool { pluggedIn || powersDevice }

    /// Name of the port station in the rows.
    var portTitle: String {
        supplies || !powersDevice ? "Charger" : "Device"
    }

    /// The port in use, e.g. "USB-C port 2". Two ports are too long for a row, so they
    /// become a count. A charger that delivers power while a device is on another port
    /// names the device's port, e.g. "Port 2 out": the charger's own port matters less.
    var portNote: String {
        guard portActive else { return "Not connected" }
        if supplies && powersDevice {
            if let only = portOut.first, portOut.count == 1 {
                return "\(only.name.replacingOccurrences(of: "USB-C p", with: "P")) out"
            }
            return "\(portOut.count) ports out"
        }
        let names = powersDevice ? portOut.map(\.name) : ports
        switch names.count {
        case 0: return "\(adapterWatts) W adapter"
        case 1: return names[0]
        default: return "\(names.count) ports"
        }
    }

    /// SF Symbol for the charge level. It has no bolt: the lit leg already says "charging".
    var levelSymbol: String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    /// The whole reading as one sentence, for VoiceOver. The loop itself is not spoken.
    /// It has no watts, like the widget.
    var spokenSummary: String {
        // The same rules as the legs of the loop.
        let battery =
            if charges {
                "Battery charging"
            } else if drains {
                "Battery draining"
            } else {
                "Battery holding"
            }
        let time = timeLeft.isEmpty ? "" : ", \(timeLeft) left"
        let charger =
            if supplies {
                "Charger connected"
            } else if pluggedIn {
                "Charger connected, delivering no power"
            } else {
                "Charger not connected"
            }
        let device = powersDevice ? " A port powers a device." : ""
        return "\(battery), \(level)\(time). \(charger).\(device)"
    }
}

/// The flow animation. A widget cannot run an animation of its own. The timeline holds one
/// entry for each step, and macOS animates from one entry to the next. A run is one unbroken
/// motion over several timelines. Its entries share a batch number.
enum Flow {
    /// Seconds from one step to the next.
    static let step: TimeInterval = 2
    /// Degrees the pulses move along the ring in one step.
    static let turn = 45.0
    /// Degrees from the start of one pulse to the start of the next.
    static let spacing = 90.0
    /// Degrees of one pulse, head and tail. The tail ends just before the next head.
    static let pulse = 84.0
    /// Width of a pulse at the end of its tail, as a share of its width at its head.
    static let tail = 0.15
    /// Share of a pulse, from its head, that has its full colour. The rest fades out.
    static let solid = 0.4
    /// Steps in one timeline. They cover the time to the next reload from the app.
    static let steps = 12
    /// Seconds a new run shows its still picture before the motion starts.
    static let lead: TimeInterval = 0.3
    /// Pace of each leg, in the order port to system, port and battery, battery to system.
    /// The small differences make two legs pass through "in step" about every half minute.
    static let paces = [1.0, 1.14, 0.88]
}

/// Rims and idle legs: the text colour, faded, so they follow light and dark.
private let rim = Color.primary.opacity(0.4)
private let idle = Color.primary.opacity(0.16)

// MARK: - Medium

struct MediumView: View {
    let sample: PowerSample
    let frame: Double
    let batch: Int

    var body: some View {
        HStack(spacing: 14) {
            LoopView(sample: sample, showsTime: false, frame: frame, batch: batch)
                .aspectRatio(1, contentMode: .fit)
            // The rows name the stations of the loop. They hold no watts: see the loop.
            VStack(spacing: 0) {
                DetailRow(
                    symbol: PowerSample.portSymbol, title: sample.portTitle, value: sample.portNote,
                    dimmed: !sample.portActive)
                Divider()
                DetailRow(
                    symbol: sample.levelSymbol, title: "Battery", value: sample.timeLeft,
                    dimmed: false)
                Divider()
                DetailRow(
                    symbol: "laptopcomputer", title: "System", value: "This Mac",
                    dimmed: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One component beside the loop: its symbol and name on the left, a note on the right.
private struct DetailRow: View {
    let symbol: String
    let title: String
    let value: String
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .opacity(dimmed ? 0.6 : 1)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - The loop

/// The energy loop. CHARGER, SYSTEM and BATTERY are three stations on a ring. A leg of the
/// ring lights up when power moves along it. Its width follows the watts.
private struct LoopView: View {
    let sample: PowerSample
    /// Show the time left under the charge level. The medium widget has it in its rows.
    let showsTime: Bool
    let frame: Double
    let batch: Int

    private static let station: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // The ring and the battery station under it fill the height.
            let radius = (size.height - Self.station - 2) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height - Self.station / 2 - 1 - radius)
            // Legs stop short of the stations, so a station needs no opaque disc to hide them.
            let loop = Loop(centre: centre, radius: radius, gap: Self.station / 2 + 3)
            ZStack {
                ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                    LegView(
                        loop: loop, leg: leg, frame: frame, batch: batch,
                        hub: UnitPoint(x: centre.x / size.width, y: centre.y / size.height))
                }
                // The inked pixels sit on the ring's centre, not the text boxes.
                middle
                    .alignmentGuide(HorizontalAlignment.center) { InkLine.inkMidX(middleLines, $0) }
                    .alignmentGuide(VerticalAlignment.center) { InkLine.inkMidY(middleLines, $0) }
                    .frame(width: radius * 1.5, height: radius * 1.5)
                    .position(centre)
                Station(symbol: PowerSample.portSymbol)
                    .opacity(sample.portActive ? 1 : 0.4)
                    .position(loop.point(Loop.port))
                Station(symbol: "laptopcomputer")
                    .position(loop.point(Loop.system))
                Station(symbol: sample.levelSymbol)
                    .position(loop.point(Loop.battery))
            }
        }
    }

    /// The three legs of the ring. Each one starts its pulses a third of a spacing after the
    /// one before, and each one has its own pace. So two lit legs drift: one leads, then they
    /// run in step, then the other leads. With one pace they would move like one mirrored
    /// picture.
    private var legs: [Leg] {
        [portToSystem, portAndBattery, batteryToSystem].enumerated().map { index, leg in
            var leg = leg
            leg.phase = Flow.spacing * Double(index) / 3
            leg.pace = Flow.paces[index]
            return leg
        }
    }

    /// A charger feeds the system. On a net loss the leg stays dark, even when the charger
    /// covers part of the load: green beside orange reads as two answers to one question.
    private var portToSystem: Leg {
        // The share of the input that the system takes. The rest goes to the battery.
        let watts = min(sample.inputW, sample.loadW)
        let lit = sample.supplies && !sample.drains
        return Leg(from: Loop.port, to: Loop.system, color: lit ? .green : nil, watts: watts)
    }

    /// The leg between the power port and the battery. It is the one leg with two directions:
    /// a charger fills the battery, or the battery feeds a device while the battery drains.
    private var portAndBattery: Leg {
        if sample.charges {
            return Leg(from: Loop.port, to: Loop.battery, color: .green, watts: sample.batteryW)
        }
        if sample.feedsDevice {
            // The power for the device comes out of the battery, not out of the system.
            return Leg(
                from: Loop.battery, to: Loop.port, color: .orange, watts: sample.deviceFromBatteryW)
        }
        return Leg(from: Loop.port, to: Loop.battery, color: nil, watts: 0)
    }

    /// The battery feeds the system. Orange marks power that leaves the battery. It is the
    /// drain colour of the terminal dashboard too.
    private var batteryToSystem: Leg {
        // What the battery gives, less the part that goes to a device.
        let watts = max(sample.drainW - sample.deviceFromBatteryW, 0)
        return Leg(
            from: Loop.battery, to: Loop.system + 360, color: sample.drains ? .orange : nil,
            watts: watts)
    }

    /// The lines in the middle of the ring, top to bottom.
    private var middleLines: [InkLine] {
        // No watts here: the legs carry the rate. The level and the time left change slowly.
        var lines = [InkLine(text: sample.level, size: 26, weight: .light)]
        if showsTime && !sample.timeLeft.isEmpty {
            lines.append(InkLine(text: sample.timeLeft, size: 11, weight: .semibold))
        }
        return lines
    }

    private var middle: some View {
        VStack(spacing: 0) {
            ForEach(Array(middleLines.enumerated()), id: \.offset) { index, line in
                Text(line.text)
                    .font(.system(size: line.size, weight: line.weight))
                    .foregroundStyle(index == 0 ? HierarchicalShapeStyle.primary : .secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// One line of text, measured by the pixels its glyphs ink. A text box is taller than its
/// digits: it keeps room for ascenders and descenders that "99%" does not have, so a
/// centred box draws the digits off centre. The ink is measured from the baseline, which
/// SwiftUI reports exactly; its line box does not follow from the font metrics.
struct InkLine {
    let text: String
    let size: CGFloat
    let weight: Font.Weight

    private var font: NSFont {
        let weights: [Font.Weight: NSFont.Weight] = [
            .light: .light, .regular: .regular, .semibold: .semibold, .bold: .bold,
        ]
        return NSFont.systemFont(ofSize: size, weight: weights[weight] ?? .regular)
    }

    /// The line's advance width and its glyphs' ink. Core Text counts x from the line's
    /// start and y up from the baseline.
    private var measure: (width: CGFloat, ink: CGRect) {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        return (width, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
    }

    /// The x of the ink's centre in a VStack of the lines, each centred across its width.
    static func inkMidX(_ lines: [InkLine], _ stack: ViewDimensions) -> CGFloat {
        let ink = lines.map(\.measure).reduce(CGRect.null) { all, line in
            all.union(line.ink.offsetBy(dx: (stack.width - line.width) / 2, dy: 0))
        }
        return ink.isNull ? stack.width / 2 : ink.midX
    }

    /// The y of the ink's centre in a VStack of the lines: from the top of the first line's
    /// ink to the bottom of the last line's ink, both measured from their baselines.
    static func inkMidY(_ lines: [InkLine], _ stack: ViewDimensions) -> CGFloat {
        guard let first = lines.first?.measure.ink, let last = lines.last?.measure.ink else {
            return stack.height / 2
        }
        let top = stack[VerticalAlignment.firstTextBaseline] - first.maxY
        let bottom = stack[VerticalAlignment.lastTextBaseline] - last.minY
        return (top + bottom) / 2
    }
}

/// The ring. Angles are degrees, counted counterclockwise from 3 o'clock.
private struct Loop {
    static let port = 150.0
    static let system = 30.0
    static let battery = 270.0

    let centre: CGPoint
    let radius: CGFloat
    /// Distance along the ring that a leg keeps clear around each station.
    let gap: CGFloat

    func point(_ degrees: Double) -> CGPoint {
        let angle = degrees * .pi / 180
        return CGPoint(x: centre.x + radius * cos(angle), y: centre.y - radius * sin(angle))
    }

    /// The arc of a leg between its two stations, as a path. It stops short of each station
    /// by the gap and by half its own width, so that its round ends stay clear of the rims.
    func arc(_ leg: Leg) -> Path {
        let short = Double((gap + leg.lineWidth / 2) / radius) * 180 / .pi
        let clear = short * (leg.to > leg.from ? 1 : -1)
        let (from, to) = (leg.from + clear, leg.to - clear)
        var path = Path()
        let steps = 40
        for step in 0...steps {
            let p = point(from + (to - from) * Double(step) / Double(steps))
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

extension Loop {
    /// Bright pulses spaced evenly round the whole ring. A leg shows the part that crosses it.
    /// A pulse is as wide as the leg at its head and thin at its tail, like a comet.
    /// `forward` is true when the pulses travel counterclockwise.
    func pulses(width: CGFloat, forward: Bool) -> Path {
        var all = Path()
        let steps = 14
        for start in stride(from: 0.0, to: 360.0, by: Flow.spacing) {
            // The two edges of the pulse, from its low angle to its high angle.
            var outer: [CGPoint] = []
            var inner: [CGPoint] = []
            for step in 0...steps {
                let share = Double(step) / Double(steps)
                // 0 at the tail, 1 at the head.
                let along = forward ? share : 1 - share
                let half = width * (Flow.tail + (1 - Flow.tail) * along) / 2
                let angle = (start + Flow.pulse * share) * .pi / 180
                let (x, y) = (cos(angle), -sin(angle))
                outer.append(CGPoint(x: centre.x + (radius + half) * x, y: centre.y + (radius + half) * y))
                inner.append(CGPoint(x: centre.x + (radius - half) * x, y: centre.y + (radius - half) * y))
            }
            var body = Path()
            body.addLines(outer + inner.reversed())
            body.closeSubpath()
            // A round head, joined to the body so that the fill has no hole.
            let head = point(start + (forward ? Flow.pulse : 0))
            let cap = Path(
                ellipseIn: CGRect(
                    x: head.x - width / 2, y: head.y - width / 2, width: width, height: width))
            all.addPath(Path(body.cgPath.union(cap.cgPath)))
        }
        return all
    }

    /// The colour of the pulses: full at each head, then fading out to nothing at the end
    /// of each tail, just before the head behind it. Gradient angles run clockwise, so a
    /// pulse lies at the end of each spacing.
    func pulseFill(_ color: Color, forward: Bool, hub: UnitPoint) -> AngularGradient {
        let space = Flow.spacing - Flow.pulse
        var stops: [Gradient.Stop] = []
        for base in stride(from: 0.0, to: 360.0, by: Flow.spacing) {
            let at = { (degrees: Double) in CGFloat((base + degrees) / 360) }
            if forward {
                // Head at the start of the pulse, tail at its end.
                stops += [
                    .init(color: .clear, location: at(0)),
                    .init(color: color, location: at(space / 2)),
                    .init(color: color, location: at(space + Flow.pulse * Flow.solid)),
                    .init(color: .clear, location: at(Flow.spacing)),
                ]
            } else {
                // Tail at the start of the pulse, head at its end.
                stops += [
                    .init(color: color, location: at(0)),
                    .init(color: .clear, location: at(space)),
                    .init(color: color, location: at(space + Flow.pulse * (1 - Flow.solid))),
                    .init(color: color, location: at(Flow.spacing)),
                ]
            }
        }
        return AngularGradient(gradient: Gradient(stops: stops), center: hub)
    }
}

/// One leg of the ring. Power moves from `from` to `to`. Nil colour is an idle leg.
private struct Leg {
    let from: Double
    let to: Double
    let color: Color?
    /// Watts on the leg. The sign is ignored.
    let watts: Double
    /// Degrees that the pulses of this leg run ahead of the others at the start of a run.
    var phase = 0.0
    /// Speed of the pulses of this leg, as a share of `Flow.turn`.
    var pace = 1.0

    /// Width of the neutral line: an idle leg, and the spaces between pulses on a live one.
    static let track: CGFloat = 2.5

    /// Width of a pulse at its head. It grows in proportion to the watts, from a thin line
    /// that stays visible at 0 W to the widest line at 100 W and more.
    var width: CGFloat { 3 + 3.5 * min(abs(watts), 100) / 100 }

    /// The widest thing the leg draws.
    var lineWidth: CGFloat { color == nil ? Self.track : max(width, Self.track) }
}


private struct LegView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let loop: Loop
    let leg: Leg
    let frame: Double
    let batch: Int
    /// The centre of the ring, as a share of the view. The pulses turn about it.
    let hub: UnitPoint

    var body: some View {
        if let color = leg.color {
            // A leg needs no arrow: the pulses run the way the power moves.
            let line = StrokeStyle(lineWidth: leg.lineWidth, lineCap: .round)
            let forward = leg.to > leg.from
            ZStack {
                if reduceMotion {
                    loop.arc(leg).stroke(color, style: line)
                } else {
                    // A neutral line, and coloured pulses that run along it. Only the pulses
                    // carry colour. Each one has a long tail that thins and fades out.
                    loop.arc(leg).stroke(idle, style: StrokeStyle(lineWidth: Leg.track, lineCap: .round))
                    loop.pulses(width: leg.width, forward: forward)
                        .fill(loop.pulseFill(color, forward: forward, hub: hub))
                        // The accent of a tinted widget style goes to the power that moves.
                        .widgetAccentable()
                        .rotationEffect(.degrees(turn), anchor: hub)
                        .mask(loop.arc(leg).stroke(style: line))
                        .animation(.linear(duration: Flow.step), value: frame)
                        // A new run is a new view. macOS then fades to it. Without this, a
                        // widget that was hidden turns the pulses through every step it
                        // missed, and the turn grows with the time it was hidden.
                        .id(batch)
                        .transition(.opacity)
                }
            }
        } else {
            loop.arc(leg).stroke(idle, style: StrokeStyle(lineWidth: Leg.track, lineCap: .round))
        }
    }

    /// How far the pulses have turned. A leg that runs counterclockwise turns them that way.
    private var turn: Double {
        (frame * Flow.turn * leg.pace + leg.phase) * (leg.to > leg.from ? -1 : 1)
    }
}

/// A station on the ring: a rim and a symbol. It has no state colour.
private struct Station: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle().strokeBorder(rim, lineWidth: 1.5)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Shared pieces

/// Shown on a Mac without a battery.
private struct NoBatteryView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 24))
            Text("No battery")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }
}
