// qos_burst.c [units]: the same main-thread-like burst of work at each quality of service, and inside an audio
// work interval with a far deadline: wall time, CPU, performance-core ms and energy of each (this process).
//   clang -O2 qos_burst.c -o qos_burst -framework AudioToolbox && ./qos_burst
// October 2026, MacBook Air M5: user-interactive and utility ~250 ms on a performance core, ~650 mJ;
// background ~870 ms on an efficiency core, ~71 mJ; the work interval changes nothing.
#include <AudioToolbox/AudioToolbox.h>
#include <os/workgroup.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdio.h>
#include <unistd.h>
#include <math.h>
static mach_timebase_info_data_t tb;
static double ms(uint64_t t) { return (double)t * tb.numer / tb.denom / 1e6; }
static void usage(uint64_t *p, uint64_t *e, uint64_t *c) {
    struct rusage_info_v6 i; proc_pid_rusage(getpid(), RUSAGE_INFO_V6, (rusage_info_t *)&i);
    *p = i.ri_user_ptime + i.ri_system_ptime; *e = i.ri_energy_nj; *c = i.ri_user_time + i.ri_system_time;
}
static volatile double sink;
static void work(long n) { double x = 1.0001; for (long i = 0; i < n; i++) { x = fmod(x * 1.0000001 + (i & 7) * 1e-9, 3.0) + 1; } sink = x; }
static void burn(const char *label, long n) {
    uint64_t p0, e0, c0, p1, e1, c1; usage(&p0, &e0, &c0); uint64_t t0 = mach_absolute_time();
    work(n);
    uint64_t t1 = mach_absolute_time(); usage(&p1, &e1, &c1);
    printf("%-28s wall %6.0f ms  cpu %6.0f ms  P %6.0f ms  energy %7.1f mJ\n", label, ms(t1 - t0), ms(c1 - c0), ms(p1 - p0), (e1 - e0) / 1e6);
    fflush(stdout);
}
int main(int argc, char **argv) {
    mach_timebase_info(&tb);
    long n = argc > 1 ? atol(argv[1]) : 40000000;
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    burn("user-interactive", n); usleep(1500000);
    pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
    burn("utility", n); usleep(1500000);
    pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0);
    burn("background", n); usleep(1500000);
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    os_workgroup_interval_t wg = AudioWorkIntervalCreate("ni-test", OS_CLOCK_MACH_ABSOLUTE_TIME, NULL);
    os_workgroup_join_token_s token; int rc = os_workgroup_join(wg, &token);
    printf("join rc %d\n", rc);
    double factors[] = {10.0, 3.0, 1.2, 10.0};
    for (int i = 0; i < 4; i++) {
        uint64_t now = mach_absolute_time();
        uint64_t deadline = now + (uint64_t)(400.0 * factors[i] * 1e6 * tb.denom / tb.numer);
        int r = os_workgroup_interval_start(wg, now, deadline, NULL);
        char label[64]; snprintf(label, sizeof label, "interval x%.1f (rc %d)", factors[i], r);
        burn(label, n);
        os_workgroup_interval_finish(wg, NULL); usleep(1500000);
    }
    burn("joined, no interval", n); usleep(1500000);
    os_workgroup_leave(wg, &token);
    burn("user-interactive again", n);
    return 0;
}
