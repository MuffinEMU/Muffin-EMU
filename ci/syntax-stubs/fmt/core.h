#pragma once
// Syntax-only shim - see ../README.md. Signatures only; no formatting is performed.
#include <string>
#include <string_view>
#include <utility>
#include <exception>
#include <type_traits>
#include <iterator>

namespace fmt {

// Real fmt puts these in its own namespace, and this codebase's formatter
// specializations rely on the unqualified names resolving there.
using string_view = std::string_view;
using wstring_view = std::wstring_view;
template <class E> constexpr auto underlying(E e) noexcept { return static_cast<__underlying_type(E)>(e); }
template <class E> using underlying_t = __underlying_type(E);

// Accepts any format string; real fmt does compile-time checking, we deliberately do not.
template <class T> struct type_identity { using type = T; };
template <class T> using type_identity_t = typename type_identity<T>::type;

template <class... A> struct basic_format_string {
    template <class S> basic_format_string(const S&) {}
    constexpr std::string_view get() const { return {}; }
};
// Aliasing through type_identity_t makes this a NON-DEDUCED context, so
// cemuLog_log(type, "x {}", v) deduces TArgs from v alone - matching real fmt.
template <class... A> using format_string = basic_format_string<type_identity_t<A>...>;
template <class... A> using wformat_string = basic_format_string<type_identity_t<A>...>;

struct format_parse_context {
    using iterator = const char*;
    constexpr iterator begin() const { return nullptr; }
    constexpr iterator end() const { return nullptr; }
    constexpr void advance_to(iterator) {}
};
struct format_context {
    using iterator = std::back_insert_iterator<std::string>;
    iterator out() { static std::string s; return std::back_inserter(s); }
    void advance_to(iterator) {}
};
template <class CharT> struct basic_format_parse_context : format_parse_context {};
template <class OutIt, class CharT> struct basic_format_context : format_context {};

// Specialized all over this codebase via `template<> struct fmt::formatter<T>`.
template <class T, class CharT = char> struct formatter {
    constexpr auto parse(format_parse_context& ctx) { return ctx.begin(); }
    template <class Ctx> auto format(const T&, Ctx& ctx) const { return ctx.out(); }
};

// runtime() wraps either narrow or wide; keep the char type so format() returns right.
template <class CharT> struct basic_runtime_format_string { std::basic_string_view<CharT> s; };
using runtime_format_string = basic_runtime_format_string<char>;
inline basic_runtime_format_string<char> runtime(std::string_view s) { return {s}; }
inline basic_runtime_format_string<wchar_t> runtime(std::wstring_view s) { return {s}; }

namespace detail {
// Which character type a format-string-ish argument implies.
template <class S> struct char_of { using type = char; };
template <> struct char_of<const wchar_t*> { using type = wchar_t; };
template <> struct char_of<wchar_t*> { using type = wchar_t; };
template <std::size_t N> struct char_of<wchar_t[N]> { using type = wchar_t; };
template <> struct char_of<std::wstring> { using type = wchar_t; };
template <> struct char_of<std::wstring_view> { using type = wchar_t; };
template <class C> struct char_of<basic_runtime_format_string<C>> { using type = C; };
template <class S> using char_of_t = typename char_of<std::remove_cv_t<std::remove_reference_t<S>>>::type;

template <class S> inline auto to_string_view(const S&) { return std::basic_string_view<char_of_t<S>>{}; }
}  // namespace detail

struct format_args { };
template <class... A> inline format_args make_format_args(A&&...) { return {}; }

// ONE generic overload. Three narrower ones made every fmt::format("x {}", y) call
// ambiguous, because a string literal matched both format_string<> and string_view.
template <class S, class... A>
inline std::basic_string<detail::char_of_t<S>> format(const S&, A&&...) { return {}; }

template <class CharT> inline std::basic_string<CharT> vformat(std::basic_string_view<CharT>, format_args) { return {}; }
template <class Out, class... A> inline Out format_to(Out o, A&&...) { return o; }
template <class Out> struct format_to_n_result { Out out; std::size_t size; };
template <class Out, class S> inline format_to_n_result<Out> vformat_to_n(Out o, std::size_t, S, format_args) { return {o, 0}; }
template <class Out, class S, class... A> inline format_to_n_result<Out> format_to_n(Out o, std::size_t, const S&, A&&...) { return {o, 0}; }
template <class... A> inline void print(A&&...) {}
template <class R, class S> inline std::string join(R&&, S&&) { return {}; }
template <class It, class S> inline std::string join(It, It, S&&) { return {}; }

struct format_error : std::exception {};

}  // namespace fmt
