// FenJing browser entry point. The manager supplies an explicit private profile.
// Launching this bundle directly opens our own manager; no upstream app is invoked.
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    char raw[PATH_MAX], binary[PATH_MAX]; uint32_t size = sizeof(raw);
    if (_NSGetExecutablePath(raw, &size) != 0 || !realpath(raw, binary)) return 1;
    char *last = strrchr(binary, '/'); if (!last) return 1; *last = 0;
    int explicit_profile = 0;
    for (int i = 1; i < argc; i++) if (strncmp(argv[i], "--user-data-dir=/", 17) == 0) explicit_profile = 1;
    if (!explicit_profile) {
        char manager[PATH_MAX]; snprintf(manager, sizeof(manager), "%s", binary);
        for (int i = 0; i < 5; i++) { char *part = strrchr(manager, '/'); if (!part) return 1; *part = 0; }
        execl("/usr/bin/open", "open", "-a", manager, (char *)NULL); return 1;
    }
    char engine[PATH_MAX]; snprintf(engine, sizeof(engine), "%s/Chromium", binary);
    argv[0] = engine; execv(engine, argv); return 1;
}
