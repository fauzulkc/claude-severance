//! Account icons: the account's own logo, or a coloured shell with its first letter.

use crate::{Account, Paths};
use ab_glyph::{Font, FontRef, PxScale, ScaleFont};
use anyhow::{Context, Result, bail};
use image::{DynamicImage, ImageReader, Rgba, RgbaImage, imageops};
use std::path::{Path, PathBuf};

pub const SIZE: u32 = 256;
pub const LOGO_TYPES: [&str; 6] = ["png", "jpg", "jpeg", "bmp", "gif", "ico"];
const MAX_LOGO_BYTES: u64 = 20 * 1024 * 1024;
/// Corner radius of the shell, as 1.x drew it (56 px arcs on 256)
const RADIUS: f32 = 28.0;

static FONT: &[u8] = include_bytes!("../../../src/fonts/IBMPlexSans-SemiBold.ttf");

/// Reads any supported image. For an .ico, the largest frame (PNG-compressed frames included).
pub fn read_image(file: &Path) -> Result<DynamicImage> {
    let img = ImageReader::open(file)
        .with_context(|| format!("couldn't open {}", file.display()))?
        .with_guessed_format()?
        .decode()
        .with_context(|| format!("{} isn't an image this can read", file.display()))?;
    Ok(img)
}

/// The image scaled to fit a transparent `size` square, centred
pub fn contain(img: &DynamicImage, size: u32) -> RgbaImage {
    let (w, h) = (img.width().max(1), img.height().max(1));
    let scale = (size as f32 / w as f32).min(size as f32 / h as f32);
    let (nw, nh) = (
        ((w as f32 * scale).round() as u32).max(1),
        ((h as f32 * scale).round() as u32).max(1),
    );
    let scaled = imageops::resize(&img.to_rgba8(), nw, nh, imageops::FilterType::Lanczos3);
    let mut out = RgbaImage::from_pixel(size, size, Rgba([0, 0, 0, 0]));
    imageops::overlay(
        &mut out,
        &scaled,
        i64::from((size - nw) / 2),
        i64::from((size - nh) / 2),
    );
    out
}

/// Copies a logo in for an account as `logos/<id>.png` (256 px on a transparent square) and returns the file name
/// to keep in accounts.json. The original can then move or go.
pub fn import_logo(source: &Path, id: &str, paths: &Paths) -> Result<String> {
    let meta = match std::fs::metadata(source) {
        Ok(m) if m.is_file() => m,
        _ => bail!("the file {} isn't there any more", source.display()),
    };
    let ext = source
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or_default()
        .to_lowercase();
    if !LOGO_TYPES.contains(&ext.as_str()) {
        bail!(
            "use a {} file",
            LOGO_TYPES.map(|t| format!(".{t}")).join(", ")
        );
    }
    if meta.len() > MAX_LOGO_BYTES {
        bail!("the file is over 20 MB");
    }
    let img = read_image(source)?;
    let dir = paths.logos();
    std::fs::create_dir_all(&dir)?;
    let name = format!("{id}.png");
    contain(&img, SIZE)
        .save(dir.join(&name))
        .with_context(|| format!("couldn't save the logo for {id}"))?;
    Ok(name)
}

/// The shell: a rounded square in `hex` with the label centred on it, black or white by contrast
pub fn letter_shell(hex: &str, label: &str, size: u32) -> RgbaImage {
    let s = size as f32 / SIZE as f32;
    let (r, g, b) = crate::color::rgb(hex);
    let mut img = RgbaImage::from_pixel(size, size, Rgba([0, 0, 0, 0]));
    let radius = RADIUS * s;
    let half = size as f32 / 2.0;
    for (x, y, px) in img.enumerate_pixels_mut() {
        // signed distance from the pixel centre to the rounded square's edge
        let qx = ((x as f32 + 0.5) - half).abs() - (half - radius);
        let qy = ((y as f32 + 0.5) - half).abs() - (half - radius);
        let outside =
            (qx.max(0.0).powi(2) + qy.max(0.0).powi(2)).sqrt() + qx.max(qy).min(0.0) - radius;
        let a = (0.5 - outside).clamp(0.0, 1.0);
        if a > 0.0 {
            *px = Rgba([r, g, b, (a * 255.0).round() as u8]);
        }
    }
    let ink: [u8; 3] = if crate::color::is_dark(hex) {
        [255, 255, 255]
    } else {
        [0, 0, 0]
    };
    let font = FontRef::try_from_slice(FONT).expect("the bundled font is valid");
    let chars = label.chars().count().max(1);
    let px = match chars {
        1 => 150.0,
        2 => 112.0,
        _ => 82.0,
    } * s;
    let scaled = font.as_scaled(PxScale::from(px));
    // lay the glyphs out on one line, then centre their visible bounds
    let mut glyphs = Vec::new();
    let mut caret = 0.0f32;
    let mut prev = None;
    for c in label.chars() {
        let id = font.glyph_id(c);
        if let Some(p) = prev {
            caret += scaled.kern(p, id);
        }
        glyphs.push(id.with_scale_and_position(px, ab_glyph::point(caret, scaled.ascent())));
        caret += scaled.h_advance(id);
        prev = Some(id);
    }
    let outlined: Vec<_> = glyphs
        .into_iter()
        .filter_map(|g| font.outline_glyph(g))
        .collect();
    if outlined.is_empty() {
        return img;
    }
    let (mut x0, mut y0, mut x1, mut y1) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
    for o in &outlined {
        let bb = o.px_bounds();
        x0 = x0.min(bb.min.x);
        y0 = y0.min(bb.min.y);
        x1 = x1.max(bb.max.x);
        y1 = y1.max(bb.max.y);
    }
    let dx = (half - (x0 + x1) / 2.0).round();
    let dy = (half - (y0 + y1) / 2.0).round();
    for o in &outlined {
        let bb = o.px_bounds();
        o.draw(|gx, gy, cov| {
            let x = (bb.min.x + dx) as i64 + i64::from(gx);
            let y = (bb.min.y + dy) as i64 + i64::from(gy);
            if x < 0 || y < 0 || x >= i64::from(size) || y >= i64::from(size) {
                return;
            }
            let p = img.get_pixel_mut(x as u32, y as u32);
            let c = cov.clamp(0.0, 1.0);
            for (channel, ink) in p.0.iter_mut().zip(ink) {
                *channel = (f32::from(ink) * c + f32::from(*channel) * (1.0 - c)).round() as u8;
            }
            p.0[3] = p.0[3].max((c * 255.0).round() as u8);
        });
    }
    img
}

/// The icon image for an account: its logo when it has a readable one, else its lettered shell
pub fn account_image(hex: &str, label: &str, logo: Option<&Path>) -> RgbaImage {
    if let Some(img) = logo.and_then(|l| read_image(l).ok()) {
        return contain(&img, SIZE);
    }
    letter_shell(hex, label, SIZE)
}

fn png_bytes(img: &RgbaImage) -> Result<Vec<u8>> {
    let mut png = Vec::new();
    DynamicImage::ImageRgba8(img.clone())
        .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)?;
    Ok(png)
}

fn write_bytes(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, bytes).with_context(|| format!("couldn't write {}", path.display()))
}

/// Writes a one-frame .ico holding a 256 px PNG, which Windows shows sharp at every size it needs
pub fn write_ico(path: &Path, img: &RgbaImage) -> Result<()> {
    let png = png_bytes(img)?;
    let mut out = Vec::with_capacity(png.len() + 22);
    out.extend_from_slice(&0u16.to_le_bytes()); // reserved
    out.extend_from_slice(&1u16.to_le_bytes()); // type: icon
    out.extend_from_slice(&1u16.to_le_bytes()); // one frame
    out.extend_from_slice(&[0, 0, 0, 0]); // 256 x 256 (0 means 256), no palette, reserved
    out.extend_from_slice(&1u16.to_le_bytes()); // planes
    out.extend_from_slice(&32u16.to_le_bytes()); // bits per pixel
    out.extend_from_slice(&(png.len() as u32).to_le_bytes());
    out.extend_from_slice(&22u32.to_le_bytes()); // offset of the frame
    out.extend_from_slice(&png);
    write_bytes(path, &out)
}

/// Writes a macOS .icns with PNG frames at 128 and 256 px (types ic07 and ic08)
pub fn write_icns(path: &Path, img: &RgbaImage) -> Result<()> {
    let mut body = Vec::new();
    for (kind, size) in [(b"ic07", 128u32), (b"ic08", 256)] {
        let frame = image::imageops::resize(img, size, size, image::imageops::FilterType::Lanczos3);
        let png = png_bytes(&frame)?;
        body.extend_from_slice(kind);
        body.extend_from_slice(&(png.len() as u32 + 8).to_be_bytes());
        body.extend_from_slice(&png);
    }
    let mut out = Vec::with_capacity(body.len() + 8);
    out.extend_from_slice(b"icns");
    out.extend_from_slice(&(body.len() as u32 + 8).to_be_bytes());
    out.extend_from_slice(&body);
    write_bytes(path, &out)
}

/// The icon file type launchers use here: .ico on Windows, .icns on macOS, .png on Linux
pub fn icon_ext() -> &'static str {
    if cfg!(windows) {
        "ico"
    } else if cfg!(target_os = "macos") {
        "icns"
    } else {
        "png"
    }
}

/// Writes `img` as this platform's icon file
pub fn write_icon(path: &Path, img: &RgbaImage) -> Result<()> {
    match icon_ext() {
        "ico" => write_ico(path, img),
        "icns" => write_icns(path, img),
        _ => write_bytes(path, &png_bytes(img)?),
    }
}

/// Writes an account's icon into `bin` and returns its path
pub fn write_account_icon(account: &Account, paths: &Paths) -> Result<PathBuf> {
    let path = paths
        .bin()
        .join(format!("icon-{}.{}", account.id, icon_ext()));
    let img = account_image(
        &account.color,
        &account.label(),
        account.logo_path(paths).as_deref(),
    );
    write_icon(&path, &img)?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo(p: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").join(p)
    }

    fn sandbox() -> (tempfile::TempDir, Paths) {
        let t = tempfile::tempdir().unwrap();
        let paths = Paths::new(t.path().join("root"), t.path().join("home"));
        (t, paths)
    }

    #[test]
    fn imports_a_png_as_logos_id_png() {
        let (_t, paths) = sandbox();
        assert_eq!(
            import_logo(&repo("assets/logo/png/mark-256.png"), "acme", &paths).unwrap(),
            "acme.png"
        );
        let a = Account {
            id: "acme".into(),
            logo: "acme.png".into(),
            ..Account::default()
        };
        let p = a.logo_path(&paths).unwrap();
        let img = image::open(p).unwrap();
        assert_eq!((img.width(), img.height()), (SIZE, SIZE));
    }

    #[test]
    fn imports_an_ico_with_png_compressed_frames() {
        let (_t, paths) = sandbox();
        assert_eq!(
            import_logo(&repo("src/assets/severance.ico"), "globex", &paths).unwrap(),
            "globex.png"
        );
    }

    #[test]
    fn refuses_a_file_that_is_not_an_image() {
        let (_t, paths) = sandbox();
        let e = import_logo(&repo("README.md"), "x", &paths).unwrap_err();
        assert!(e.to_string().contains("use a"), "{e}");
    }

    #[test]
    fn refuses_a_missing_file() {
        let (t, paths) = sandbox();
        let e = import_logo(&t.path().join("gone.png"), "x", &paths).unwrap_err();
        assert!(e.to_string().contains("isn't there"), "{e}");
    }

    #[test]
    fn builds_an_icon_from_a_logo_and_from_a_letter_when_the_logo_is_unusable() {
        let (t, _paths) = sandbox();
        for (name, logo) in [
            ("a.ico", repo("assets/logo/png/mark-256.png")),
            ("b.ico", repo("README.md")),
        ] {
            let f = t.path().join(name);
            write_ico(&f, &account_image("#C08A2E", "A", Some(&logo))).unwrap();
            let bytes = std::fs::read(&f).unwrap();
            assert_eq!(u16::from_le_bytes([bytes[2], bytes[3]]), 1, "an icon file");
            assert_eq!(u16::from_le_bytes([bytes[4], bytes[5]]), 1, "one frame");
            // and Windows (or anything else) can read it back
            let back = image::load_from_memory(&bytes).unwrap();
            assert_eq!(back.width(), SIZE);
        }
    }

    #[test]
    fn the_letter_is_drawn_in_contrast_at_the_centre() {
        let dark = letter_shell("#3E6FA3", "I", SIZE);
        let centre = dark.get_pixel(SIZE / 2, SIZE / 2);
        assert!(
            centre.0[0] > 200 && centre.0[3] == 255,
            "white letter on a dark shell: {centre:?}"
        );
        let corner = dark.get_pixel(0, 0);
        assert_eq!(corner.0[3], 0, "rounded corners are transparent");
        let light = letter_shell("#F9F1A5", "I", SIZE);
        assert!(
            light.get_pixel(SIZE / 2, SIZE / 2).0[0] < 60,
            "black letter on a light shell"
        );
    }
}
