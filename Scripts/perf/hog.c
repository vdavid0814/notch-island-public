// N threads spinning at a given QoS for S seconds: ./hog N S [utility|default|initiated]
#include <pthread.h>
#include <pthread/qos.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static qos_class_t q = QOS_CLASS_DEFAULT;
static void *spin(void *a){ pthread_set_qos_class_self_np(q, 0); volatile double x = 0; for(;;) x += 1.5; return NULL; }
int main(int c, char **v){ int n = c > 1 ? atoi(v[1]) : 10; int s = c > 2 ? atoi(v[2]) : 30;
  if (c > 3) q = !strcmp(v[3], "utility") ? QOS_CLASS_UTILITY : !strcmp(v[3], "initiated") ? QOS_CLASS_USER_INITIATED : QOS_CLASS_DEFAULT;
  pthread_t t; for (int i = 0; i < n; i++) pthread_create(&t, NULL, spin, NULL); sleep(s); return 0; }
