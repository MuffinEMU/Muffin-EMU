#include "Cafe/HW/Latte/ISA/RegDefines.h"
#include "Cafe/HW/Latte/Core/Latte.h"
#include "Cafe/HW/Latte/Core/LatteDraw.h"

#include "Cafe/HW/Latte/Core/LatteQueryObject.h"
#include "Cafe/HW/Latte/Core/LatteWaitInfo.h"

#include <chrono>
#include <thread>
#include "Cafe/HW/Latte/Renderer/Renderer.h"

#define GPU7_QUERY_TYPE_OCCLUSION	(1)

uint64 queryEventCounter = 1;

struct LatteGX2QueryInformation
{
	MPTR queryMPTR;
	uint64 queryEventStart;
	uint64 queryEventEnd;
	uint64 sampleSum;
	bool queryEnded;
};

std::vector<LatteGX2QueryInformation*> list_activeGX2Queries2;

std::vector<LatteQueryObject*> list_queriesInFlight;

uint64 latestQueryFinishedEventId = 0;

LatteQueryObject* _currentlyActiveRendererQuery = {0};

uint64 LatteQuery_getNextEventId()
{
	uint64 ev = queryEventCounter;
	queryEventCounter++;
	return ev;
}

void LatteQuery_begin(LatteQueryObject* queryObject, uint64 eventId)
{
	queryObject->queryEventStart = eventId;
	queryObject->begin();
}

void LatteQuery_end(LatteQueryObject* queryObject, uint64 eventId)
{
	cemu_assert_debug(!queryObject->queryEnded);
	queryObject->queryEnded = true;
	queryObject->queryEventEnd = eventId;
	queryObject->end();
}

LatteQueryObject* LatteQuery_createSamplePassedQuery()
{
	return g_renderer->occlusionQuery_create();
}

void LatteQuery_finishGX2Query(LatteGX2QueryInformation* gx2Query)
{
	uint32* queryObjectData = (uint32*)memory_getPointerFromVirtualOffset(gx2Query->queryMPTR);
	*(uint64*)(queryObjectData + 0) = 0;
	*(uint64*)(queryObjectData + 2) = gx2Query->sampleSum;
	*(uint64*)(queryObjectData + 4) = 0;
	*(uint64*)(queryObjectData + 6) = 0;

	*(uint64*)(queryObjectData + 8) = 0; // overwrites the 'OCPU' magic constant letting GX2QueryGetOcclusionResult know that the query is finished (for CPU queries)
}

void LatteQuery_UpdateFinishedQueries()
{
	g_renderer->occlusionQuery_updateState();
	for(uint32 i=0; i<list_queriesInFlight.size(); i++)
	{
		LatteQueryObject* queryObject = list_queriesInFlight[i];
		cemu_assert_debug(queryObject->queryEnded);
		if( queryObject->queryEnded == false )
			continue;
		// check if result is available
		uint64 numSamplesPassed;
		if (!queryObject->getResult(numSamplesPassed))
			break;

		cemu_assert_debug(latestQueryFinishedEventId < queryObject->queryEventEnd);
		latestQueryFinishedEventId = queryObject->queryEventEnd;

		// add number of passed samples to all gx2 queries that were active at the time
		for (auto& it : list_activeGX2Queries2)
		{
			if (queryObject->queryEventStart >= it->queryEventStart && queryObject->queryEventEnd <= it->queryEventEnd)
				it->sampleSum += numSamplesPassed;
		}

		list_queriesInFlight.erase(list_queriesInFlight.begin() + i);
		i--;
		g_renderer->occlusionQuery_destroy(queryObject);
	}
	LatteWait::Get().queriesInFlight.store((uint32)list_queriesInFlight.size(), std::memory_order_relaxed);
	// check for finished GX2 queries
	for (sint32 i = 0; i < list_activeGX2Queries2.size(); i++)
	{
		auto gx2Query = list_activeGX2Queries2[i];
		if (gx2Query->queryEnded && latestQueryFinishedEventId >= gx2Query->queryEventEnd)
		{
			LatteQuery_finishGX2Query(gx2Query);
			free(gx2Query);
			list_activeGX2Queries2.erase(list_activeGX2Queries2.begin() + i);
			i--;
		}
	}
}

void LatteQuery_UpdateFinishedQueriesForceFinishAll()
{
	cemu_assert_debug(_currentlyActiveRendererQuery == nullptr);
	LatteWait::Scope waitScope("waiting for occlusion query results (sync)");
	g_renderer->occlusionQuery_flush(); // guarantees that all query commands have been submitted and finished processing
	// This used to spin until every query was in the finished state. A query that is still open (a
	// nested GX2 query keeps a renderer query running) or whose GPU result never arrives is never
	// removed from the list, and the GPU thread then spun here for good while the game carried on.
	const auto start = std::chrono::steady_clock::now();
	while (true)
	{
		LatteQuery_UpdateFinishedQueries();
		if (list_queriesInFlight.empty())
			break;
		if (std::chrono::steady_clock::now() - start > std::chrono::milliseconds(1500))
		{
			size_t unended = 0;
			for (auto* q : list_queriesInFlight)
				unended += q->queryEnded ? 0 : 1;
			static uint32 s_giveUps = 0;
			if (s_giveUps++ < 8)
				cemuLog_log(LogType::Force, "Latte: gave up waiting for {} occlusion queries ({} still open) after 1500 ms", list_queriesInFlight.size(), unended);
			LatteWait::Get().timeouts.fetch_add(1);
			LatteWait::Get().lastTimeoutReason.store("waiting for occlusion query results (sync)");
			break;
		}
		std::this_thread::yield();
	}
}

sint32 checkQueriesCounter = 0;

void LatteQuery_endActiveRendererQuery(uint64 currentEventId)
{
	if (_currentlyActiveRendererQuery != nullptr)
	{
		LatteQuery_end(_currentlyActiveRendererQuery, currentEventId);
		list_queriesInFlight.emplace_back(_currentlyActiveRendererQuery);
		_currentlyActiveRendererQuery = nullptr;
		LatteWait::Get().queriesInFlight.store((uint32)list_queriesInFlight.size(), std::memory_order_relaxed);
	}
}

void LatteQuery_BeginOcclusionQuery(MPTR queryMPTR)
{
	if (checkQueriesCounter < 7)
	{
		checkQueriesCounter++;
	}
	else
	{
		LatteQuery_UpdateFinishedQueries();
		checkQueriesCounter = 0;
	}

	for(auto& it : list_activeGX2Queries2)
	{
		if (it->queryMPTR == queryMPTR)
		{
			debug_printf("itHLEBeginOcclusionQuery: Query 0x%08x is already active\n", queryMPTR);
			return;
		}
	}
	uint64 currentEventId = LatteQuery_getNextEventId();
	// end any currently active query
	LatteQuery_endActiveRendererQuery(currentEventId);
	// create GX2 query binding
	LatteGX2QueryInformation* queryBinding = (LatteGX2QueryInformation*)malloc(sizeof(LatteGX2QueryInformation));
	memset(queryBinding, 0x00, sizeof(LatteGX2QueryInformation));
	queryBinding->queryEventStart = currentEventId;
	queryBinding->queryMPTR = queryMPTR;
	list_activeGX2Queries2.emplace_back(queryBinding);
	// start renderer query
	LatteQueryObject* queryObject = LatteQuery_createSamplePassedQuery();
	LatteQuery_begin(queryObject, currentEventId);
	_currentlyActiveRendererQuery = queryObject;
}

void LatteQuery_EndOcclusionQuery(MPTR queryMPTR)
{
	if (queryMPTR == MPTR_NULL)
		return;
	uint64 currentEventId = LatteQuery_getNextEventId();
	// mark query binding as ended
	for(auto& it : list_activeGX2Queries2)
	{
		if (it->queryMPTR == queryMPTR)
		{
			it->queryEventEnd = currentEventId;
			it->queryEnded = true;
			break;
		}
	}
	// end currently active renderer query
	LatteQuery_endActiveRendererQuery(currentEventId);
	// check if there are still active GX2 queries
	bool hasActiveGX2Query = false;
	for (auto& it : list_activeGX2Queries2)
	{
		if (!it->queryEnded)
		{
			hasActiveGX2Query = true;
			break;
		}
	}
	// start a new renderer query if there are still active GX2 queries
	if (hasActiveGX2Query)
	{
		LatteQueryObject* queryObject = LatteQuery_createSamplePassedQuery();
		LatteQuery_begin(queryObject, currentEventId);
		list_queriesInFlight.emplace_back(queryObject);
		_currentlyActiveRendererQuery = queryObject;
		catchOpenGLError();
	}
}

void LatteQuery_CancelActiveGPU7Queries()
{
	cemu_assert_debug(_currentlyActiveRendererQuery == nullptr);
}

void LatteQuery_Init()
{
}

// Called when the GPU thread is shutting down, while the renderer still exists. The query lists are process-wide:
// whatever a stopped title left in them belongs to a renderer that is about to be destroyed (the query objects), or
// to guest memory that the next title will reuse (the GX2 query bindings write their result to a guest address
// when they finish). Dropped, not finished: nothing is waiting for these results any more.
void LatteQuery_Reset()
{
	if (g_renderer)
	{
		if (_currentlyActiveRendererQuery)
			g_renderer->occlusionQuery_destroy(_currentlyActiveRendererQuery);
		for (LatteQueryObject* queryObject : list_queriesInFlight)
			g_renderer->occlusionQuery_destroy(queryObject);
	}
	_currentlyActiveRendererQuery = nullptr;
	list_queriesInFlight.clear();
	for (LatteGX2QueryInformation* gx2Query : list_activeGX2Queries2)
		free(gx2Query);
	list_activeGX2Queries2.clear();
	queryEventCounter = 1;
	latestQueryFinishedEventId = 0;
	checkQueriesCounter = 0;
	LatteWait::Get().queriesInFlight.store(0, std::memory_order_relaxed);
}

// for the post-teardown check: number of query objects and GX2 query bindings still tracked
size_t LatteQuery_GetTrackedCount()
{
	return list_queriesInFlight.size() + list_activeGX2Queries2.size() + (_currentlyActiveRendererQuery ? 1 : 0);
}