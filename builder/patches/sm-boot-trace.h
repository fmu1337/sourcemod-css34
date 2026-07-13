/**
 * css34 boot trace — append-only log for smoke/gdb hang diagnosis.
 * Enabled when SM_BOOT_TRACE is defined at compile time.
 */
#ifndef SM_BOOT_TRACE_H
#define SM_BOOT_TRACE_H

#include <stdio.h>
#include <stdarg.h>
#include <sys/time.h>

#ifdef SM_BOOT_TRACE

static inline void sm_boot_trace(const char *where)
{
	FILE *f = fopen("/tmp/sm-boot-trace.log", "a");
	if (!f)
		return;

	struct timeval tv;
	gettimeofday(&tv, NULL);
	fprintf(f, "[%ld.%03ld] %s\n", (long)(tv.tv_sec % 100000), (long)(tv.tv_usec / 1000), where);
	fflush(f);
	fclose(f);
}

static inline void sm_boot_tracef(const char *fmt, ...)
{
	FILE *f = fopen("/tmp/sm-boot-trace.log", "a");
	if (!f)
		return;

	struct timeval tv;
	gettimeofday(&tv, NULL);
	fprintf(f, "[%ld.%03ld] ", (long)(tv.tv_sec % 100000), (long)(tv.tv_usec / 1000));

	va_list ap;
	va_start(ap, fmt);
	vfprintf(f, fmt, ap);
	va_end(ap);

	fprintf(f, "\n");
	fflush(f);
	fclose(f);
}

#else

static inline void sm_boot_trace(const char *) {}
static inline void sm_boot_tracef(const char *, ...) {}

#endif

#endif /* SM_BOOT_TRACE_H */
