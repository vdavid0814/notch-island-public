// What `ThriftWatch` relies on: a thread at background quality of service gets almost no processor
// when every core is taken, another thread can see that in its CPU time (thread_info), and an
// override from outside (pthread_override_qos_class_start_np) lifts it at once.
//
//   cc -O1 thrift_watch.c -o thrift_watch
//   ./thrift_watch            a fixed amount of work at background, read every 40 ms
//   ./thrift_watch rescue     the same, lifted once it has missed 80 ms
// Beside `./hog 10 60 utility` (all ten cores taken): 2 s of work took 10.2 s; with the rescue 1.95 s
// (lifted 0.8 s in by this tool's rule; the app's own, `StallMeter`, fades and lifts ~0.1 s in).
#include <pthread.h>
#include <pthread/qos.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static double now(void){ return clock_gettime_nsec_np(CLOCK_UPTIME_RAW)/1e9; }
static volatile int done = 0; static volatile double finished = 0;
static void *worker(void *arg){
  pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0);
  double own0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)/1e9;
  volatile double x = 0; for (long i = 0; i < 600000000L; i++) x += i * 0.5;   // a fixed amount of work
  double own1 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)/1e9;
  finished = now(); done = 1; printf("worker cpu by own clock %.0f ms\n", (own1-own0)*1000); return NULL;
}
static double cpu_of(thread_t t, int *state){
  thread_basic_info_data_t info; mach_msg_type_number_t n = THREAD_BASIC_INFO_COUNT;
  if (thread_info(t, THREAD_BASIC_INFO, (thread_info_t)&info, &n) != KERN_SUCCESS) return -1;
  *state = info.run_state;
  return info.user_time.seconds + info.user_time.microseconds/1e6 + info.system_time.seconds + info.system_time.microseconds/1e6;
}
int main(int argc, char **argv){
  int rescue = argc > 1 && !strcmp(argv[1], "rescue");
  pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
  pthread_t th; pthread_create(&th, NULL, worker, NULL); thread_t port = pthread_mach_thread_np(th);
  double start = now(), last = start, starved = 0; int st; double lastcpu = cpu_of(port, &st); pthread_override_t ov = NULL; double rescuedAt = 0;
  while (!done) {
    usleep(40000); double t = now(); double cpu = cpu_of(port, &st); double dt = t-last, ran = cpu-lastcpu;
    if (ran < dt*0.25 && st == TH_STATE_RUNNING) starved += dt;
    if (!rescuedAt || t - rescuedAt < 0.2) printf("  +%4.0f ms: ran %5.1f of %5.1f ms, state %d, starved %.0f ms\n", (t-start)*1000, ran*1000, dt*1000, st, starved*1000);
    if (rescue && !ov && starved >= 0.08) { ov = pthread_override_qos_class_start_np(th, QOS_CLASS_USER_INTERACTIVE, 0); rescuedAt = t; printf("  RESCUED at +%.0f ms\n", (t-start)*1000); }
    last = t; lastcpu = cpu;
  }
  pthread_join(th, NULL); if (ov) pthread_override_qos_class_end_np(ov);
  printf("wall %.0f ms, starved %.0f ms%s\n", (finished-start)*1000, starved*1000, rescue ? " (with rescue)" : "");
}
