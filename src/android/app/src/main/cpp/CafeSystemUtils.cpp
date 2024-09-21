#include "CafeSystemUtils.h"

#include "Cafe/CafeSystem.h"
#include "Cafe/TitleList/TitleList.h"

namespace CafeSystemUtils
{
	void startGame(const fs::path& launchPath)
	{
		TitleInfo launchTitle{launchPath};
		if (launchTitle.IsValid())
		{
			// the title might not be in the TitleList, so we add it as a temporary entry
			CafeTitleList::AddTitleFromPath(launchPath);
			// title is valid, launch from TitleId
			TitleId baseTitleId;
			if (!CafeTitleList::FindBaseTitleId(launchTitle.GetAppTitleId(), baseTitleId))
			{
				throw GameBaseFilesNotFoundException();
			}
			CafeSystem::STATUS_CODE r = CafeSystem::PrepareForegroundTitle(baseTitleId);
			if (r != CafeSystem::STATUS_CODE::SUCCESS)
			{
				throw UnknownGameFilesException();
			}
		}
		else // if (launchTitle.GetFormat() == TitleInfo::TitleDataFormat::INVALID_STRUCTURE )
		{
			// title is invalid, if it's an RPX/ELF we can launch it directly
			// otherwise it's an error
			CafeTitleFileType fileType = DetermineCafeSystemFileType(launchPath);
			if (fileType == CafeTitleFileType::RPX || fileType == CafeTitleFileType::ELF)
			{
				CafeSystem::STATUS_CODE r = CafeSystem::PrepareForegroundTitleFromStandaloneRPX(launchPath);
				if (r != CafeSystem::STATUS_CODE::SUCCESS)
				{
					throw UnknownGameFilesException();
				}
			}
			else if (launchTitle.GetInvalidReason() == TitleInfo::InvalidReason::NO_DISC_KEY)
			{
				throw NoDiscKeyException();
			}
			else if (launchTitle.GetInvalidReason() == TitleInfo::InvalidReason::NO_TITLE_TIK)
			{
				throw NoTitleTikException();
			}
			else
			{
				throw UnknownGameFilesException();
			}
		}
		CafeSystem::LaunchForegroundTitle();
	}
}; // namespace CafeSystemUtils