// Host-side unit test for ios/Bridge/IOSAuditFrameStats.h. Built and run by the audit workflow's
// "checks" job with the compiler every Mac runner has; no engine headers involved.
#include "IOSAuditFrameStats.h"
#include <cstdio>
#include <cstdlib>
#include <vector>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static std::vector<uint8_t> makeFrame(uint32_t w, uint32_t h, uint8_t r, uint8_t g, uint8_t b, ios_audit::PixelLayout layout)
{
	std::vector<uint8_t> f((size_t)w * h * 4);
	for (size_t i = 0; i < (size_t)w * h; ++i)
	{
		uint8_t* p = &f[i * 4];
		if (layout == ios_audit::PixelLayout::BGRA8) { p[0] = b; p[1] = g; p[2] = r; }
		else { p[0] = r; p[1] = g; p[2] = b; }
		p[3] = 255;
	}
	return f;
}

int main()
{
	using namespace ios_audit;
	const uint32_t W = 320, H = 180, TW = 16, TH = 9;
	std::vector<uint8_t> thumb((size_t)TW * TH * 3);
	FrameStats s;

	// Solid red, both channel orders.
	for (auto layout : {PixelLayout::RGBA8, PixelLayout::BGRA8})
	{
		auto f = makeFrame(W, H, 200, 10, 30, layout);
		ComputeStatsAndThumb(f.data(), W, H, W * 4, layout, TW, TH, thumb.data(), s);
		CHECK(std::abs(s.meanR - 200.0f) < 0.01f);
		CHECK(std::abs(s.meanG - 10.0f) < 0.01f);
		CHECK(std::abs(s.meanB - 30.0f) < 0.01f);
		CHECK(s.blackFraction == 0.0f);
		CHECK(thumb[0] == 200 && thumb[1] == 10 && thumb[2] == 30);
		CHECK(thumb[(TW * TH - 1) * 3] == 200);
	}

	// All black is all black.
	{
		auto f = makeFrame(W, H, 0, 0, 0, PixelLayout::RGBA8);
		ComputeStatsAndThumb(f.data(), W, H, W * 4, PixelLayout::RGBA8, TW, TH, thumb.data(), s);
		CHECK(s.blackFraction == 1.0f);
		CHECK(s.maxLuma == 0);
	}

	// Left half white, right half black: thumbnail columns follow, and the white share is one half.
	{
		auto f = makeFrame(W, H, 0, 0, 0, PixelLayout::RGBA8);
		for (uint32_t y = 0; y < H; ++y)
			for (uint32_t x = 0; x < W / 2; ++x)
			{
				uint8_t* p = &f[((size_t)y * W + x) * 4];
				p[0] = p[1] = p[2] = 255;
			}
		ComputeStatsAndThumb(f.data(), W, H, W * 4, PixelLayout::RGBA8, TW, TH, thumb.data(), s);
		CHECK(std::abs(s.whiteFraction - 0.5f) < 0.001f);
		CHECK(std::abs(s.blackFraction - 0.5f) < 0.001f);
		CHECK(thumb[(0 * TW + 3) * 3] == 255);
		CHECK(thumb[(0 * TW + 12) * 3] == 0);
		CHECK(s.minLuma == 0 && s.maxLuma == 255);
	}

	// Hash: equal frames equal, one changed pixel differs. Row pitch larger than the row is honoured.
	{
		auto a = makeFrame(W, H, 10, 20, 30, PixelLayout::RGBA8);
		auto b = a;
		FrameStats sa, sb;
		ComputeStatsAndThumb(a.data(), W, H, W * 4, PixelLayout::RGBA8, TW, TH, nullptr, sa);
		ComputeStatsAndThumb(b.data(), W, H, W * 4, PixelLayout::RGBA8, TW, TH, nullptr, sb);
		CHECK(sa.hash == sb.hash);
		b[((size_t)90 * W + 100) * 4] ^= 0x01;
		ComputeStatsAndThumb(b.data(), W, H, W * 4, PixelLayout::RGBA8, TW, TH, nullptr, sb);
		CHECK(sa.hash != sb.hash);

		const uint32_t pitch = W * 4 + 64;
		std::vector<uint8_t> padded((size_t)pitch * H, 0xEE);
		for (uint32_t y = 0; y < H; ++y)
			std::copy(a.begin() + (size_t)y * W * 4, a.begin() + (size_t)(y + 1) * W * 4, padded.begin() + (size_t)y * pitch);
		FrameStats sp;
		ComputeStatsAndThumb(padded.data(), W, H, pitch, PixelLayout::RGBA8, TW, TH, nullptr, sp);
		CHECK(std::abs(sp.meanR - 10.0f) < 0.01f);
	}

	// RGB10A2: R = 1023 is 255 after the shift.
	{
		std::vector<uint8_t> f((size_t)W * H * 4);
		for (size_t i = 0; i < (size_t)W * H; ++i)
		{
			uint32_t v = 1023u | (0u << 10) | (512u << 20) | (3u << 30);
			std::memcpy(&f[i * 4], &v, 4);
		}
		ComputeStatsAndThumb(f.data(), W, H, W * 4, PixelLayout::RGB10A2, TW, TH, thumb.data(), s);
		CHECK(std::abs(s.meanR - 255.0f) < 0.01f);
		CHECK(std::abs(s.meanG - 0.0f) < 0.01f);
		CHECK(std::abs(s.meanB - 128.0f) < 0.01f);
	}

	// Degenerate input must not crash.
	ComputeStatsAndThumb(nullptr, 0, 0, 0, PixelLayout::RGBA8, TW, TH, thumb.data(), s);

	if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
	std::printf("frame_stats_test: all checks passed\n");
	return 0;
}
