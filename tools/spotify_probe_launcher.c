#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

extern char** environ;

int main(int argc, char* argv[]) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s /path/to/Spotify [args...]\n", argv[0]);
    return 64;
  }

  signal(SIGHUP, SIG_IGN);
  setsid();

  execve(argv[1], &argv[1], environ);
  fprintf(stderr, "execve failed for %s: %s\n", argv[1], strerror(errno));
  return 127;
}

