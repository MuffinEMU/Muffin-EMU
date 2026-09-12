#pragma once
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
namespace boost {
inline void to_lower(std::string& s){ std::transform(s.begin(),s.end(),s.begin(),[](unsigned char c){return (char)std::tolower(c);} ); }
inline void to_upper(std::string& s){ std::transform(s.begin(),s.end(),s.begin(),[](unsigned char c){return (char)std::toupper(c);} ); }
inline std::string to_lower_copy(std::string s){ to_lower(s); return s; }
inline std::string to_upper_copy(std::string s){ to_upper(s); return s; }
inline void trim(std::string&){}
inline std::string trim_copy(std::string s){ return s; }
template <class R, class T> bool iequals(const R& a, const T& b){ (void)a;(void)b; return false; }
template <class Seq, class Rng, class Pred> void split(Seq& out, const Rng&, Pred){ (void)out; }
inline bool starts_with(const std::string&, const std::string&){ return false; }
inline bool ends_with(const std::string&, const std::string&){ return false; }
inline void replace_all(std::string&, const std::string&, const std::string&){}
namespace algorithm { using boost::iequals; using boost::split; }
}
