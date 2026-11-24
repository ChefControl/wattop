//! Open-laptop outline, seen from the front, that shows which physical port the charger uses.

use crate::{flow, panel};
use ratatui::{
    Frame,
    layout::Rect,
    style::{Color, Style, Stylize},
    text::{Line, Span},
    widgets::Paragraph,
};
use wattop::telemetry::Sample;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Left,
    Right,
}

/// One physical port. `slot` counts from the back (1) to the front (`slots`).
#[derive(Debug, PartialEq, Eq)]
pub struct PortPos {
    /// Name as `Sample.power_ports` spells it, e.g. "USB-C port 2". Never-powered ports use their own name.
    pub name: &'static str,
    /// Short label drawn on the outline, e.g. "USB-C 2".
    pub short: &'static str,
    pub side: Side,
    pub slot: u8,
    pub slots: u8,
}

/// Power-capable ports per model. Only verified layouts are listed. Never guess.
/// Non-power ports (HDMI, SD, audio) are left out on purpose.
const MAC16_1: &[PortPos] = &[
    PortPos {
        name: "MagSafe",
        short: "MagSafe",
        side: Side::Left,
        slot: 1,
        slots: 4,
    },
    PortPos {
        name: "USB-C port 2",
        short: "USB-C 2",
        side: Side::Left,
        slot: 2,
        slots: 4,
    },
    PortPos {
        name: "USB-C port 1",
        short: "USB-C 1",
        side: Side::Left,
        slot: 3,
        slots: 4,
    },
    PortPos {
        name: "USB-C port 4",
        short: "USB-C 4",
        side: Side::Right,
        slot: 2,
        slots: 3,
    },
];

/// Port table for a `hw.model` id. None when the layout is not verified.
pub fn layout(model: &str) -> Option<&'static [PortPos]> {
    match model {
        "Mac16,1" => Some(MAC16_1),
        _ => None,
    }
}

/// Reads `hw.model`, e.g. "Mac16,1". Empty when sysctl fails.
pub fn model() -> String {
    std::process::Command::new("sysctl")
        .args(["-n", "hw.model"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_owned())
        .unwrap_or_default()
}

/// Widest row of the drawing: the front edge of the deck.
const BODY_W: i32 = 18;
/// Screen (4 rows) above the deck (4 rows).
const BODY_H: i32 = 8;
/// Width that leaves room for labels and cables on both sides.
const LABEL_W: i32 = 36;
/// First deck row. The screen takes the rows above it.
const DECK_Y: i32 = 4;
/// Cells between the left end of the front edge and the left edge of the hinge row.
const DECK_INSET: i32 = 3;

/// Deck row for a port: 0 at the hinge (back) to 3 at the front edge.
fn deck_row(p: &PortPos) -> i32 {
    (p.slot as i32 - 1) * 3 / (p.slots as i32 - 1).max(1)
}

pub fn draw(f: &mut Frame, area: Rect, s: &Sample, ports: Option<&'static [PortPos]>) {
    let watts = if s.plugged_in {
        format!(" in {:.1} W ", s.input_w)
    } else {
        " on battery ".into()
    };
    let block = panel("ports").title_bottom(Span::styled(
        watts,
        Style::new().fg(Color::LightGreen).bold(),
    ));
    let inner = block.inner(area);
    f.render_widget(block, area);

    let fits = inner.width as i32 >= BODY_W && inner.height as i32 >= BODY_H;
    match ports {
        Some(ports) if fits => outline(f, inner, s, ports),
        _ => list(f, inner, s),
    }
}

/// Fallback when the model is unknown or the panel is too small.
fn list(f: &mut Frame, inner: Rect, s: &Sample) {
    let lines: Vec<Line> = if s.power_ports.is_empty() && s.port_out.is_empty() {
        vec![Line::from("no power port".dark_gray())]
    } else {
        s.power_ports
            .iter()
            .map(|p| Line::from(p.clone()).light_green().bold())
            .chain(s.port_out.iter().map(|o| {
                Line::from(format!("{} ▸ {:.1} W", o.name, o.watts))
                    .fg(flow::ORANGE)
                    .bold()
            }))
            .collect()
    };
    f.render_widget(Paragraph::new(lines), inner);
}

fn outline(f: &mut Frame, inner: Rect, s: &Sample, ports: &[PortPos]) {
    let w = inner.width as i32;
    let x0 = (w - BODY_W) / 2; // left end of the front edge
    let labels = w >= LABEL_W;
    let dim = Style::new().fg(Color::DarkGray);
    let buf = f.buffer_mut();

    // An open laptop seen from the front. The deck widens by one cell per row toward the viewer.
    let art = [
        "   ╭──────────╮",
        "   │          │",
        "   │          │",
        "   ╰──────────╯",
        "   ╱▪▪▪▪▪▪▪▪▪▪╲",
        "  ╱▪▪▪▪▪▪▪▪▪▪▪▪╲",
        " ╱     ╶──╴     ╲",
        "╱▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁╲",
    ];
    for (y, line) in art.iter().enumerate() {
        for (x, ch) in line.chars().enumerate().filter(|(_, ch)| *ch != ' ') {
            flow::put(buf, inner, x0 + x as i32, y as i32, &ch.to_string(), dim);
        }
    }

    for p in ports {
        let d = deck_row(p);
        let y = DECK_Y + d;
        let on = s.power_ports.iter().any(|n| n == p.name);
        let out = s.port_out.iter().any(|o| o.name == p.name);
        let style = if on {
            Style::new().fg(Color::LightGreen).bold()
        } else if out {
            Style::new().fg(flow::ORANGE).bold()
        } else {
            dim
        };
        let len = p.short.chars().count() as i32;
        // The deck edge on the port's row takes the port's colour.
        // `cable` is the two cells between the label and the edge, read left to right.
        let (edge, slash, cable, label) = match p.side {
            Side::Left => {
                let edge = x0 + DECK_INSET - d;
                let cable = if on { "═▶" } else { "◀═" };
                (edge, "╱", (edge - 2, cable), (edge - 3 - len).max(0))
            }
            Side::Right => {
                let edge = x0 + BODY_W - 1 - DECK_INSET + d;
                let cable = if on { "◀═" } else { "═▶" };
                (edge, "╲", (edge + 1, cable), (edge + 4).min(w - len))
            }
        };
        flow::put(buf, inner, edge, y, slash, style);
        if !labels {
            continue;
        }
        if on || out {
            flow::put_str(buf, inner, cable.0, y, cable.1, style);
        }
        flow::put_str(buf, inner, label, y, p.short, style);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{Terminal, backend::TestBackend};
    use wattop::telemetry::PortOut;

    #[test]
    fn powering_port_draws_orange_arrow_away_from_body() {
        let s = Sample {
            port_out: vec![PortOut {
                name: "USB-C port 2".into(),
                watts: 11.5,
            }],
            ..Default::default()
        };
        let ports = layout("Mac16,1").unwrap();
        let mut terminal = Terminal::new(TestBackend::new(40, 9)).unwrap();
        terminal.draw(|f| outline(f, f.area(), &s, ports)).unwrap();
        let buf = terminal.backend().buffer();
        assert!(
            buf.content()
                .iter()
                .any(|c| c.symbol() == "◀" && c.fg == flow::ORANGE)
        );
    }

    #[test]
    fn usb_c_2_is_left_slot_2_of_4_on_mac16_1() {
        let ports = layout("Mac16,1").unwrap();
        let p = ports.iter().find(|p| p.name == "USB-C port 2").unwrap();
        assert_eq!((p.side, p.slot, p.slots), (Side::Left, 2, 4));
    }

    #[test]
    fn mac16_1_lists_only_power_ports() {
        let ports = layout("Mac16,1").unwrap();
        assert_eq!(ports.len(), 4);
        assert!(
            ports
                .iter()
                .all(|p| p.name == "MagSafe" || p.name.starts_with("USB-C")),
            "non-power port in layout: {ports:?}"
        );
    }

    #[test]
    fn slots_map_to_deck_rows_from_the_hinge() {
        // Mac16,1: three left ports on adjacent rows at the back, one right port on the second row.
        let ports = layout("Mac16,1").unwrap();
        assert_eq!(ports.iter().map(deck_row).collect::<Vec<_>>(), [0, 1, 2, 1]);
    }

    #[test]
    fn charging_port_draws_green_arrow_into_body() {
        let s = Sample {
            plugged_in: true,
            power_ports: vec!["USB-C port 1".into()],
            ..Default::default()
        };
        let ports = layout("Mac16,1").unwrap();
        let mut terminal = Terminal::new(TestBackend::new(40, 9)).unwrap();
        terminal.draw(|f| outline(f, f.area(), &s, ports)).unwrap();
        let buf = terminal.backend().buffer();
        // Slot 3 of 4 sits on the third deck row, below the four screen rows.
        let arrow = buf
            .content()
            .iter()
            .position(|c| c.symbol() == "▶" && c.fg == Color::LightGreen)
            .expect("green arrow");
        assert_eq!(arrow / 40, 6);
        // The deck edge next to the arrow takes the port's colour.
        assert_eq!(buf.content()[arrow + 1].symbol(), "╱");
        assert_eq!(buf.content()[arrow + 1].fg, Color::LightGreen);
    }

    /// Renders the outline on a `w` x 9 buffer and returns its rows as text.
    fn render(s: &Sample, model: &str, w: u16) -> Vec<String> {
        let ports = layout(model).unwrap();
        let mut terminal = Terminal::new(TestBackend::new(w, 9)).unwrap();
        terminal.draw(|f| outline(f, f.area(), s, ports)).unwrap();
        let buf = terminal.backend().buffer();
        buf.content()
            .chunks(w as usize)
            .map(|row| row.iter().map(|c| c.symbol()).collect())
            .collect()
    }

    #[test]
    fn open_laptop_has_empty_screen_and_labels_on_port_rows() {
        let s = Sample {
            plugged_in: true,
            power_ports: vec!["USB-C port 1".into()],
            ..Default::default()
        };
        let rows = render(&s, "Mac16,1", 36);
        assert_eq!(
            rows,
            [
                "            ╭──────────╮            ",
                "            │          │            ",
                "            │          │            ",
                "            ╰──────────╯            ",
                "  MagSafe   ╱▪▪▪▪▪▪▪▪▪▪╲            ",
                " USB-C 2   ╱▪▪▪▪▪▪▪▪▪▪▪▪╲   USB-C 4 ",
                "USB-C 1 ═▶╱     ╶──╴     ╲          ",
                "         ╱▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁╲         ",
                "                                    ",
            ]
        );
    }

    #[test]
    fn right_side_port_keeps_label_and_cable_inside_the_panel() {
        let s = Sample {
            port_out: vec![PortOut {
                name: "USB-C port 4".into(),
                watts: 11.5,
            }],
            ..Default::default()
        };
        let rows = render(&s, "Mac16,1", 36);
        assert_eq!(rows[5], " USB-C 2   ╱▪▪▪▪▪▪▪▪▪▪▪▪╲═▶ USB-C 4 ");
    }

    #[test]
    fn narrow_panel_draws_the_laptop_without_labels() {
        let rows = render(&Sample::default(), "Mac16,1", 20);
        assert_eq!(rows[4], "    ╱▪▪▪▪▪▪▪▪▪▪╲    ");
        assert!(rows.iter().all(|r| !r.contains("USB-C")));
    }

    #[test]
    fn unknown_model_has_no_layout() {
        assert!(layout("MacBookPro99,1").is_none());
    }
}
