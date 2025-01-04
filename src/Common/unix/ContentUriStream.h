#pragma once

#include <boost/iostreams/device/file_descriptor.hpp>
#include <boost/iostreams/stream_buffer.hpp>

#include "Common/unix/FilesystemAndroid.h"

class ContentUriStream : public boost::iostreams::stream_buffer<boost::iostreams::file_descriptor_source>, public std::istream
{
  public:
	explicit ContentUriStream(const std::filesystem::path& path)
		: boost::iostreams::stream_buffer<boost::iostreams::file_descriptor_source>(FilesystemAndroid::openContentUri(path), boost::iostreams::close_handle), std::istream(this) {}

	bool is_open()
	{
		return component()->is_open();
	}
};