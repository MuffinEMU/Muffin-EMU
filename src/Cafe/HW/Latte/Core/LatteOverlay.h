#pragma once

#include <atomic>
#include <string>
#include <vector>

void LatteOverlay_init();
void LatteOverlay_render(bool pad_view);
void LatteOverlay_updateStats(double fps, sint32 drawcalls, sint32 fastDrawcalls);

void LatteOverlay_pushNotification(const std::string& text, sint32 duration);

#if BOOST_OS_IOS
// iOS draws the overlay and notifications natively in SwiftUI instead of with ImGui.
// While g_overlayNativeOnIOS is true, LatteOverlay_render() draws nothing.
extern std::atomic_bool g_overlayNativeOnIOS;

// Builds the text the ImGui overlay would show, from the same config flags and timing.
// stats: one entry per line of the stats block. notifications: one entry per notification
// card, with a card's own lines separated by '\n'. Both are appended to.
void LatteOverlay_CollectNativeText(std::vector<std::string>& stats, std::vector<std::string>& notifications);
#endif
