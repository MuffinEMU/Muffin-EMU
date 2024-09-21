#pragma once

#include "Cafe/TitleList/TitleId.h"

namespace CafeSystemUtils
{
	class GameFilesException : public std::exception
	{
	  public:
		explicit GameFilesException(const std::string& message)
			: m_message(message) {}

		const char* what() const noexcept override
		{
			return m_message.c_str();
		}

	  private:
		std::string m_message;
	};

	class GameBaseFilesNotFoundException : public GameFilesException
	{
	  public:
		GameBaseFilesNotFoundException()
			: GameFilesException("Game base files not found.") {}
	};

	class NoDiscKeyException : public GameFilesException
	{
	  public:
		NoDiscKeyException()
			: GameFilesException("No disc key found.") {}
	};

	class NoTitleTikException : public GameFilesException
	{
	  public:
		NoTitleTikException()
			: GameFilesException("No title ticket found.") {}
	};

	class UnknownGameFilesException : public GameFilesException
	{
	  public:
		UnknownGameFilesException()
			: GameFilesException("Unknown error occurred during game launch.") {}
	};

	void startGame(const fs::path& launchPath);
}; // namespace CafeSystemUtils