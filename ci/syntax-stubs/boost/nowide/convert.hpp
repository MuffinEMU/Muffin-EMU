#pragma once
#include <string>
namespace boost { namespace nowide {
inline std::string narrow(const std::wstring&){ return {}; }
inline std::string narrow(const wchar_t*){ return {}; }
inline std::wstring widen(const std::string&){ return {}; }
inline std::wstring widen(const char*){ return {}; }
}}
