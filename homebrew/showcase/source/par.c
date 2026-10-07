// Small fork-join job pool. par_run() splits one job into PAR_JOBS slices: slice 0 runs on the
// calling thread, slices 1 and 2 on two OSThreads pinned to PPC cores 0 and 2. If the threads
// cannot be created every slice simply runs on the caller, so scenes never depend on the pool.
#include "showcase.h"

#include <coreinit/cache.h>
#include <coreinit/semaphore.h>
#include <coreinit/thread.h>

#define PSTACK 0x10000
#define NWORK (PAR_JOBS - 1)

static OSThread s_th[NWORK] __attribute__((aligned(16)));
static u8 s_stack[NWORK][PSTACK] __attribute__((aligned(16)));
static OSSemaphore s_go[NWORK], s_done[NWORK];
static volatile int s_quit, s_ok, s_init;
static void (*volatile s_fn)(void *, int, int);
static void *volatile s_ctx;

static int worker(int id, const char **argv)
{
   (void)argv;
   for (;;)
   {
      OSWaitSemaphore(&s_go[id]);
      if (s_quit) break;
      s_fn(s_ctx, id + 1, PAR_JOBS);
      OSSignalSemaphore(&s_done[id]);
   }
   return 0;
}

void par_init(void)
{
   if (s_init) return;
   s_init = 1;
   s_ok = 1;
   for (int i = 0; i < NWORK; i++)
   {
      OSInitSemaphore(&s_go[i], 0);
      OSInitSemaphore(&s_done[i], 0);
   }
   for (int i = 0; i < NWORK; i++)
   {
      int cpu = i == 0 ? OS_THREAD_ATTRIB_AFFINITY_CPU0 : OS_THREAD_ATTRIB_AFFINITY_CPU2;
      if (!OSCreateThread(&s_th[i], worker, i, NULL, s_stack[i] + PSTACK, PSTACK, 16, (OSThreadAttributes)cpu))
      {
         // Threads that did start must still be woken to exit; fewer than NWORK means serial mode.
         s_ok = 0;
         for (int k = 0; k < i; k++) { s_quit = 1; OSSignalSemaphore(&s_go[k]); }
         return;
      }
      OSSetThreadName(&s_th[i], "showcase pool");
      OSResumeThread(&s_th[i]);
   }
}

void par_run(void (*fn)(void *ctx, int job, int njobs), void *ctx)
{
   if (!s_init) par_init();
   if (!s_ok)
   {
      for (int j = 0; j < PAR_JOBS; j++) fn(ctx, j, PAR_JOBS);
      return;
   }
   s_fn = fn;
   s_ctx = ctx;
   for (int i = 0; i < NWORK; i++) OSSignalSemaphore(&s_go[i]);
   fn(ctx, 0, PAR_JOBS);
   for (int i = 0; i < NWORK; i++) OSWaitSemaphore(&s_done[i]);
}

// The three PPC cores do not share a coherent cache. Main publishes what workers read, each slice
// flushes what it wrote, and main invalidates before reading the result.
void par_publish(const void *p, size_t n) { DCFlushRange((void *)p, (uint32_t)n); }
void par_consume(const void *p, size_t n) { DCInvalidateRange((void *)p, (uint32_t)n); }
void par_flush(const void *p, size_t n) { DCFlushRange((void *)p, (uint32_t)n); }   // slice: after writing

void par_shutdown(void)
{
   if (!s_init || !s_ok) return;
   s_quit = 1;
   for (int i = 0; i < NWORK; i++) OSSignalSemaphore(&s_go[i]);
   for (int i = 0; i < NWORK; i++) { int rc; OSJoinThread(&s_th[i], &rc); }
   s_ok = 0;
}
