// Wii U console accounts and each one's Network Service for iOS. Account
// (Cafe/Account/Account.h) and per-account Network Service selection
// (CemuConfig::GetAccountNetworkService/SetAccountSelectedService, config/NetworkSettings.h)
// are both complete, already-working desktop Cemu features - the same account.dat files
// and the same network_services.xml override desktop reads - that had no iOS surface at
// all before this. Ported from MeloCafe's Account.swift/NetworkService.swift/
// CreateAccountView.swift, which drive the identical C++ API through an Obj-C class
// wrapper (CemuConfigWrapper); this file gives MuffinEMU's own plain-C cemu_bridge_*
// boundary the same data instead, in the delimited-record shape
// IOSGraphicPacks_List() already established for "a list of structured things" here.
#include "Cafe/Account/Account.h"
#include "Cafe/CafeSystem.h"
#include "Cemu/ncrypto/ncrypto.h"
#include "config/CemuConfig.h"
#include "config/NetworkSettings.h"

#include <boost/nowide/convert.hpp>
#include <sstream>
#include <string>
#include <string_view>

namespace
{
	// account.dat's miiName/email are free text - a real console lets someone type
	// almost anything into either field, and so does this app's own create form. Strip
	// the two characters this wire format uses as its own record/field separators so a
	// pasted value can never forge a second record; both are non-printable control
	// characters no legitimate Mii name or email needs.
	std::string SanitizeField(std::string_view value)
	{
		std::string result;
		result.reserve(value.size());
		for (char c : value)
		{
			if (c != '\x1E' && c != '\x1F')
				result.push_back(c);
		}
		return result;
	}

	const Account* FindAccount(uint32 persistentId)
	{
		for (const auto& account : Account::GetAccounts())
		{
			if (account.GetPersistentId() == persistentId)
				return &account;
		}
		return nullptr;
	}

	// Every account field setter follows the same shape as CemuConfigWrapper.mm's own
	// setMiiName/setGender/etc: load the account's own file fresh rather than mutating
	// the cached Account::GetAccounts() copy in place, save, then refresh the cache so
	// the next cemu_bridge_accounts_list() reflects the change.
	template <typename Mutator>
	bool MutateAccount(uint32 persistentId, Mutator&& mutator)
	{
		Account account(Account::GetFileName(persistentId).wstring());
		if (account.Load())
			return false;
		mutator(account);
		if (account.Save())
			return false;
		Account::RefreshAccounts();
		return true;
	}
}

void IOSAccounts_Refresh()
{
	Account::RefreshAccounts();
}

std::string IOSAccounts_List()
{
	std::ostringstream out;
	const auto& accounts = Account::GetAccounts();
	for (size_t i = 0; i < accounts.size(); i++)
	{
		if (i != 0)
			out << '\x1E';
		const auto& account = accounts[i];
		out << fmt::format("{:08x}", account.GetPersistentId()) << '\x1F'
			<< SanitizeField(boost::nowide::narrow(std::wstring(account.GetMiiName()))) << '\x1F'
			<< account.GetBirthYear() << '\x1F'
			<< (int)account.GetBirthMonth() << '\x1F'
			<< (int)account.GetBirthDay() << '\x1F'
			<< (int)account.GetGender() << '\x1F'
			<< SanitizeField(account.GetEmail()) << '\x1F'
			<< account.GetCountry() << '\x1F'
			<< (account.IsValidOnlineAccount() ? '1' : '0');
	}
	return out.str();
}

bool IOSAccounts_HasFreeSlot()
{
	return Account::HasFreeAccountSlots();
}

uint32_t IOSAccounts_NextPersistentId()
{
	return Account::GetNextPersistentId();
}

uint32_t IOSAccounts_MinPersistentId()
{
	return Account::kMinPersistendId;
}

bool IOSAccounts_Locked()
{
	return CafeSystem::IsTitleRunning();
}

bool IOSAccounts_Create(uint32_t persistentId, const char* miiName, uint16_t birthYear,
	uint8_t birthMonth, uint8_t birthDay, int gender, const char* email, int country)
{
	Account::RefreshAccounts();

	if (!Account::HasFreeAccountSlots())
		return false;
	if (persistentId < Account::kMinPersistendId)
		return false;
	if (FindAccount(persistentId) != nullptr)
		return false;
	if (!miiName || miiName[0] == '\0')
		return false;

	try
	{
		const std::wstring wideName = boost::nowide::widen(miiName);
		Account account(persistentId, wideName);
		account.SetBirthYear(birthYear);
		account.SetBirthMonth(birthMonth);
		account.SetBirthDay(birthDay);
		account.SetGender((uint8)gender);
		if (email)
			account.SetEmail(email);
		account.SetCountry((uint32)country);

		if (account.Save())
			return false;
	}
	catch (const std::exception&)
	{
		// Account's constructor throws on an invalid mii name/persistent id, both of
		// which are already checked above - this only remains as a backstop.
		return false;
	}

	Account::RefreshAccounts();
	return true;
}

bool IOSAccounts_Delete(uint32_t persistentId)
{
	Account::RefreshAccounts();

	if (Account::GetAccounts().size() == 1)
		return false;
	if (FindAccount(persistentId) == nullptr)
		return false;

	const fs::path path = Account::GetFileName(persistentId).parent_path();
	std::error_code ec;
	fs::remove_all(path, ec);
	if (ec)
		return false;

	Account::RefreshAccounts();
	return true;
}

bool IOSAccounts_SetMiiName(uint32_t persistentId, const char* miiName)
{
	if (!miiName || miiName[0] == '\0')
		return false;
	return MutateAccount(persistentId, [&](Account& account) {
		account.SetMiiName(boost::nowide::widen(miiName));
	});
}

bool IOSAccounts_SetGender(uint32_t persistentId, int gender)
{
	return MutateAccount(persistentId, [&](Account& account) {
		account.SetGender((uint8)gender);
	});
}

bool IOSAccounts_SetEmail(uint32_t persistentId, const char* email)
{
	return MutateAccount(persistentId, [&](Account& account) {
		account.SetEmail(email ? email : "");
	});
}

bool IOSAccounts_SetCountry(uint32_t persistentId, int country)
{
	return MutateAccount(persistentId, [&](Account& account) {
		account.SetCountry((uint32)country);
	});
}

bool IOSAccounts_SetBirthdate(uint32_t persistentId, uint16_t year, uint8_t month, uint8_t day)
{
	return MutateAccount(persistentId, [&](Account& account) {
		account.SetBirthYear(year);
		account.SetBirthMonth(month);
		account.SetBirthDay(day);
	});
}

uint32_t IOSAccounts_ActivePersistentId()
{
	return GetConfig().account.m_persistent_id.GetValue();
}

void IOSAccounts_SetActivePersistentId(uint32_t persistentId)
{
	GetConfig().account.m_persistent_id = persistentId;
}

bool IOSAccounts_IsOnlineValid(uint32_t persistentId)
{
	const Account* account = FindAccount(persistentId);
	return account && account->IsValidOnlineAccount();
}

std::string IOSAccounts_CountriesList()
{
	std::ostringstream out;
	bool first = true;
	for (int i = 0; i < NCrypto::GetCountryCount(); ++i)
	{
		const char* country = NCrypto::GetCountryAsString(i);
		if (!country || (i != 0 && std::string(country) == "NN"))
			continue;
		if (!first)
			out << '\x1E';
		first = false;
		out << i << '\x1F' << country;
	}
	return out.str();
}

int IOSAccounts_NetworkService(uint32_t persistentId)
{
	return (int)GetConfig().GetAccountNetworkService(persistentId);
}

void IOSAccounts_SetNetworkService(uint32_t persistentId, int service)
{
	if (service < (int)NetworkService::Offline || service > (int)NetworkService::Custom)
		return;
	GetConfig().SetAccountSelectedService(persistentId, (NetworkService)service);
}

bool IOSAccounts_CustomNetworkServiceAvailable()
{
	return NetworkConfig::XMLExists();
}
