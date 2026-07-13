/**
 * css34 boot trace — append-only log for smoke/gdb hang diagnosis.
 * Enabled when SM_BOOT_TRACE is defined at compile time.
 */
#ifndef SM_BOOT_TRACE_H
#define SM_BOOT_TRACE_H

#include <stdio.h>
#include <stdarg.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/time.h>
#endif

#ifdef SM_BOOT_TRACE

static inline FILE *sm_boot_trace_open(void)
{
#ifdef _WIN32
	char path[MAX_PATH];
	DWORD n = GetTempPathA(MAX_PATH, path);
	if (n == 0 || n >= MAX_PATH)
		return NULL;
	if (lstrlenA(path) + 18 >= MAX_PATH)
		return NULL;
	lstrcatA(path, "sm-boot-trace.log");
	return fopen(path, "a");
#else
	return fopen("/tmp/sm-boot-trace.log", "a");
#endif
}

static inline void sm_boot_trace_timestamp(long *sec_part, long *msec_part)
{
#ifdef _WIN32
	FILETIME ft;
	ULARGE_INTEGER uli;

	GetSystemTimeAsFileTime(&ft);
	uli.LowPart = ft.dwLowDateTime;
	uli.HighPart = ft.dwHighDateTime;
	/* 100-ns intervals since 1601-01-01; show sub-day seconds like Linux. */
	unsigned long long ms = uli.QuadPart / 10000ULL;
	*sec_part = (long)((ms / 1000ULL) % 100000ULL);
	*msec_part = (long)(ms % 1000ULL);
#else
	struct timeval tv;

	gettimeofday(&tv, NULL);
	*sec_part = (long)(tv.tv_sec % 100000);
	*msec_part = (long)(tv.tv_usec / 1000);
#endif
}

static inline void sm_boot_trace(const char *where)
{
	FILE *f = sm_boot_trace_open();
	long sec_part;
	long msec_part;

	if (!f)
		return;

	sm_boot_trace_timestamp(&sec_part, &msec_part);
	fprintf(f, "[%ld.%03ld] %s\n", sec_part, msec_part, where);
	fflush(f);
	fclose(f);
}

static inline void sm_boot_tracef(const char *fmt, ...)
{
	FILE *f = sm_boot_trace_open();
	long sec_part;
	long msec_part;
	va_list ap;

	if (!f)
		return;

	sm_boot_trace_timestamp(&sec_part, &msec_part);
	fprintf(f, "[%ld.%03ld] ", sec_part, msec_part);

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
