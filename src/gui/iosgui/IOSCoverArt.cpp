// Derives the 6-character GameTDB Game ID (e.g. "AGME01" for the US release of
// Splatoon) from a title's own meta.xml, so the iOS app can fetch real box art for a
// game automatically on import instead of falling back to the in-game icon or a
// placeholder.
//
// The 6 characters are exactly: the last 4 characters of product_code (meta.xml's
// "WUP-P-AGME" -> "AGME" - the region already lives in the 4th character, there is no
// separate region lookup needed) followed by the last 2 characters of company_code
// ("0001" -> "01", Nintendo's own publisher suffix). Verified against GameTDB's live
// site rather than assumed: https://www.gametdb.com/WiiU/AGME01 is the real Splatoon
// (US) page, and https://art.gametdb.com/wiiu/cover/US/AGME01.jpg resolves with a real
// image - the derivation and the download path were both checked against the actual
// service before writing this, not guessed from a spec.
//
// A title with unset metadata carries the documented placeholder values instead of a
// real code - "WUP-P-ABCD" / company code "ZZZZ" (see WiiUBrew's meta.xml page) - and
// deriving a lookup ID from those would confidently try to fetch art for a game that
// was never identified at all, so they are rejected explicitly rather than treated as
// a normal (if unlikely) product code.
#include "Cafe/TitleList/TitleInfo.h"

#include <algorithm>
#include <cctype>
#include <string>

namespace
{
std::string ToUpper(std::string s)
{
	std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::toupper(c); });
	return s;
}
} // namespace

std::string IOSCoverArt_DeriveGameTdbId(const char* romPath)
{
	if (!romPath || romPath[0] == '\0')
		return {};

	TitleInfo titleInfo{fs::path(romPath)};
	if (!titleInfo.IsValid() || !titleInfo.HasValidXmlInfo())
		return {};

	ParsedMetaXml* meta = titleInfo.GetMetaInfo();
	if (!meta)
		return {};

	std::string productCode = ToUpper(meta->GetProductCode());
	std::string companyCode = ToUpper(meta->GetCompanyCode());

	// Expected shape "WUP-P-XXXX" - take the last 4 characters rather than assuming a
	// fixed offset, since some titles (system titles, per WiiUBrew) use different
	// leading segments.
	if (productCode.size() < 4 || companyCode.size() < 2)
		return {};
	std::string gameCode = productCode.substr(productCode.size() - 4);
	std::string publisherSuffix = companyCode.substr(companyCode.size() - 2);

	if (gameCode == "ABCD" || companyCode == "ZZZZ")
		return {}; // documented placeholder values - no real identity to look up

	return gameCode + publisherSuffix;
}
