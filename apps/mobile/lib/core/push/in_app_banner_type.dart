/// Severity of an in-app banner — drives the left border colour + icon chip (design #82).
///
/// Lives in its own Flutter-free file so the PURE push classifier ([pushBannerType] in
/// `push_banner.dart`) can return it without importing the widget layer (`in_app_banner.dart`,
/// which depends on Flutter). The toast widget re-exports it for call-site convenience.
enum InAppBannerType { success, error, info, warning }
