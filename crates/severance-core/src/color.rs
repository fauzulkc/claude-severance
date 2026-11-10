//! Account colours.

/// `#RRGGBB` to (r, g, b); anything else reads as mid grey, like 1.x
pub fn rgb(hex: &str) -> (u8, u8, u8) {
    let h = hex.trim().trim_start_matches('#');
    if h.len() == 6 && h.chars().all(|c| c.is_ascii_hexdigit()) {
        let p = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0x88);
        (p(0), p(2), p(4))
    } else {
        (0x88, 0x88, 0x88)
    }
}

/// Dark enough to need white text on it
pub fn is_dark(hex: &str) -> bool {
    let (r, g, b) = rgb(hex);
    0.299 * f64::from(r) + 0.587 * f64::from(g) + 0.114 * f64::from(b) < 150.0
}

/// A terminal badge: ` L ` in the account's colour, with black or white text
pub fn badge(hex: &str, label: &str) -> String {
    let (r, g, b) = rgb(hex);
    let fg = if is_dark(hex) {
        "38;2;255;255;255"
    } else {
        "38;2;0;0;0"
    };
    format!("\x1b[48;2;{r};{g};{b}m\x1b[{fg}m\x1b[1m {label} \x1b[0m")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_hex_and_falls_back_to_grey() {
        assert_eq!(rgb("#3E6FA3"), (0x3e, 0x6f, 0xa3));
        assert_eq!(rgb("nope"), (0x88, 0x88, 0x88));
    }

    #[test]
    fn knows_dark_from_light() {
        assert!(is_dark("#3E6FA3"));
        assert!(!is_dark("#F9F1A5"));
    }
}
