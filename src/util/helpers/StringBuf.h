#pragma once

class StringBuf
{
public:
	StringBuf(uint32 bufferSize)
	{
		this->allocated = true;
		this->length = 0;
		this->oom = false;
		// under memory pressure a large malloc can fail. Retry with smaller sizes, the buffer grows on demand
		this->str = nullptr;
		this->limit = 0;
		uint32 trySize = bufferSize;
		while (true)
		{
			this->str = (uint8*)malloc((size_t)trySize + 4);
			if (this->str)
			{
				this->limit = trySize;
				this->str[0] = '\0';
				break;
			}
			if (trySize <= 4096)
			{
				this->oom = true;
				this->limit = 0;
				break;
			}
			trySize /= 2;
		}
	}

	~StringBuf()
	{
		if (this->allocated)
			free(this->str);
	}

	// true if memory could not be allocated. All further writes are ignored in this state
	bool isOutOfMemory() const
	{
		return this->oom;
	}

	template<typename TFmt, typename ... TArgs>
	void addFmt(const TFmt& format, TArgs&&... args)
	{
		if (this->oom)
			return;
		while (true)
		{
			size_t avail = (size_t)(this->limit - this->length);
			auto r = fmt::vformat_to_n((char*)(this->str + this->length), avail, fmt::detail::to_string_view(format), fmt::make_format_args(args...));
			if ((size_t)r.size < avail)
			{
				this->length += (uint32)r.size;
				return;
			}
			// output did not fit, grow and format again
			if (!_reserve(std::max<size_t>((size_t)this->length + r.size + 64, (size_t)this->limit + this->limit / 2)))
				return;
		}
	}

	void add(const char* appendedStr)
	{
		if (!appendedStr)
			return;
		add(std::string_view(appendedStr));
	}

	void add(std::string_view appendedStr)
	{
		if (this->oom)
			return;
		size_t copyLen = appendedStr.size();
		if ((size_t)this->length + copyLen + 1 >= this->limit)
		{
			if (!_reserve(std::max<size_t>((size_t)this->length + copyLen + 64, (size_t)this->limit + this->limit / 2)))
				return;
		}
		char* outputStart = (char*)(this->str + this->length);
		std::copy(appendedStr.data(), appendedStr.data() + copyLen, outputStart);
		length += copyLen;
		outputStart[copyLen] = '\0';
	}

	void reset()
	{
		length = 0;
	}

	uint32 getLen() const
	{
		return length;
	}

	const char* c_str() const
	{
		if (!str)
			return "";
		str[length] = '\0';
		return (const char*)str;
	}

	void shrink_to_fit()
	{
		if (!this->allocated || this->oom)
			return;
		uint32 newLimit = this->length;
		uint8* newStr = (uint8*)realloc(this->str, (size_t)newLimit + 4);
		if (!newStr)
			return; // keep the old (larger) buffer
		this->str = newStr;
		this->limit = newLimit;
	}

private:
	bool _reserve(size_t newLimit)
	{
		if (newLimit > 0xFFFFFFF0u)
			newLimit = 0xFFFFFFF0u;
		if (newLimit <= this->limit)
		{
			this->oom = true;
			return false;
		}
		uint8* newStr = (uint8*)realloc(this->str, newLimit + 4);
		if (!newStr)
		{
			// old buffer stays valid but cannot hold more. Drop further output
			this->oom = true;
			return false;
		}
		this->str = newStr;
		this->limit = (uint32)newLimit;
		return true;
	}

	uint8*	str;
	uint32	length; /* in bytes */
	uint32	limit; /* in bytes */
	bool	allocated;
	bool	oom;
};