//! Writes a contact sheet of lettered shells, one per palette colour, to compare with 1.x:
//!   cargo run -p severance-core --example icon-sheet -- out.png
use severance_core::{account::PALETTE, icon};

fn main() {
    let out = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "icon-sheet.png".into());
    let labels = ["P", "A", "G", "I", "U", "9", "W", "M"];
    let mut sheet =
        image::RgbaImage::from_pixel(8 * 136 + 8, 144, image::Rgba([246, 244, 239, 255]));
    for (i, (hex, label)) in PALETTE.iter().zip(labels).enumerate() {
        let tile = image::imageops::resize(
            &icon::letter_shell(hex, label, 256),
            128,
            128,
            image::imageops::FilterType::Lanczos3,
        );
        image::imageops::overlay(&mut sheet, &tile, 8 + i as i64 * 136, 8);
    }
    sheet.save(&out).expect("saved");
    println!("{out}");
}
