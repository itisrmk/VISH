//! Root view shown inside the NSPanel — search field + mock result rows.

use gpui::{
    AppContext as _, Context, Entity, Focusable as _, IntoElement, ParentElement as _, Render,
    Styled as _, Window, div,
};
use gpui_component::input::{Input, InputState};
use gpui_component::v_flex;

use crate::theme::Theme;

const MOCK_ROWS: [(&str, &str); 4] = [
    ("Terminal.app", "Application"),
    ("Safari.app", "Application"),
    ("Calendar.app", "Application"),
    ("Settings", "System Preferences"),
];

pub struct RootView {
    theme: Theme,
    input_state: Entity<InputState>,
}

impl RootView {
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let input_state = cx.new(|cx| InputState::new(window, cx).placeholder("Search…"));
        let handle = input_state.read(cx).focus_handle(cx);
        window.focus(&handle, cx);
        Self {
            theme: Theme::dark(),
            input_state,
        }
    }
}

impl Render for RootView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let colors = &self.theme.colors;
        let spacing = &self.theme.spacing;
        let typography = &self.theme.typography;

        v_flex()
            .size_full()
            .p(spacing.md)
            .gap(spacing.sm)
            .bg(colors.background)
            .border_1()
            .border_color(colors.border)
            .rounded(spacing.sm)
            .font_family(&typography.font_family)
            .text_color(colors.foreground)
            .text_size(typography.size_md)
            .child(Input::new(&self.input_state))
            .children(MOCK_ROWS.iter().map(|(label, hint)| {
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap(spacing.md)
                    .px(spacing.md)
                    .py(spacing.sm)
                    .rounded(spacing.xs)
                    .child(
                        div()
                            .w(spacing.lg)
                            .h(spacing.lg)
                            .rounded(spacing.xs)
                            .bg(colors.muted_foreground),
                    )
                    .child(div().flex_1().text_color(colors.foreground).child(*label))
                    .child(
                        div()
                            .text_size(typography.size_sm)
                            .text_color(colors.muted_foreground)
                            .child(*hint),
                    )
            }))
    }
}
