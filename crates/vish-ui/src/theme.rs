//! Hardcoded color, spacing, and typography tokens.
//!
//! Color field names mirror Zed's `ThemeColors` where practical:
//! `background`, `foreground` (Zed: `text`), `muted_foreground` (Zed: `text_muted`),
//! `border`, `accent` (Zed: `text_accent`).

use gpui::{Hsla, Pixels, SharedString, hsla, px};

pub struct Theme {
    pub colors: Colors,
    pub spacing: Spacing,
    pub typography: Typography,
}

pub struct Colors {
    pub background: Hsla,
    pub foreground: Hsla,
    pub muted_foreground: Hsla,
    pub border: Hsla,
    pub accent: Hsla,
}

pub struct Spacing {
    pub xs: Pixels,
    pub sm: Pixels,
    pub md: Pixels,
    pub lg: Pixels,
    pub xl: Pixels,
}

pub struct Typography {
    pub font_family: SharedString,
    pub size_sm: Pixels,
    pub size_md: Pixels,
}

const SPACING: Spacing = Spacing {
    xs: px(4.),
    sm: px(8.),
    md: px(12.),
    lg: px(16.),
    xl: px(24.),
};

impl Theme {
    pub fn dark() -> Self {
        Self {
            colors: Colors {
                background: hsla(220. / 360., 0.13, 0.10, 0.92),
                foreground: hsla(0., 0., 0.96, 1.),
                muted_foreground: hsla(0., 0., 0.62, 1.),
                border: hsla(0., 0., 1., 0.08),
                accent: hsla(212. / 360., 0.96, 0.62, 1.),
            },
            spacing: SPACING,
            typography: Typography {
                font_family: SharedString::new_static(".SystemUIFont"),
                size_sm: px(12.),
                size_md: px(14.),
            },
        }
    }

    pub fn light() -> Self {
        Self {
            colors: Colors {
                background: hsla(0., 0., 0.98, 0.92),
                foreground: hsla(0., 0., 0.09, 1.),
                muted_foreground: hsla(0., 0., 0.42, 1.),
                border: hsla(0., 0., 0., 0.10),
                accent: hsla(212. / 360., 0.96, 0.50, 1.),
            },
            spacing: SPACING,
            typography: Typography {
                font_family: SharedString::new_static(".SystemUIFont"),
                size_sm: px(12.),
                size_md: px(14.),
            },
        }
    }
}
