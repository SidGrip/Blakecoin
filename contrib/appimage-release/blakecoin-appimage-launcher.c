#define _GNU_SOURCE

#include <errno.h>
#include <gnu/libc-version.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int parse_glibc_version(int *major, int *minor) {
    const char *version = gnu_get_libc_version();

    if (version == NULL || sscanf(version, "%d.%d", major, minor) != 2) {
        return -1;
    }

    return 0;
}

int main(int argc, char **argv) {
    char self_path[PATH_MAX];
    char app_dir[PATH_MAX];
    char payload_path[PATH_MAX];
    char **exec_argv = NULL;
    ssize_t len;
    char *slash;
    int glibc_major = 0;
    int glibc_minor = 0;
    int i;

    if (parse_glibc_version(&glibc_major, &glibc_minor) == 0) {
        if (glibc_major < 2 || (glibc_major == 2 && glibc_minor < 34)) {
            fprintf(stderr, "This Blakecoin AppImage bundle supports Ubuntu 22.04 and newer.\n");
            fprintf(stderr, "Use the Ubuntu 20 native release on older systems.\n");
            return 1;
        }
    }

    len = readlink("/proc/self/exe", self_path, sizeof(self_path) - 1);
    if (len < 0) {
        perror("readlink");
        return 1;
    }
    self_path[len] = '\0';

    if (snprintf(app_dir, sizeof(app_dir), "%s", self_path) >= (int)sizeof(app_dir)) {
        fprintf(stderr, "Launcher path is too long\n");
        return 1;
    }

    slash = strrchr(app_dir, '/');
    if (slash == NULL) {
        fprintf(stderr, "Could not determine launcher directory\n");
        return 1;
    }
    *slash = '\0';

    if (snprintf(payload_path, sizeof(payload_path), "%s/.runtime/Blakecoin-0.15.2-x86_64.AppImage.payload", app_dir) >= (int)sizeof(payload_path)) {
        fprintf(stderr, "Payload path is too long\n");
        return 1;
    }

    if (access(payload_path, X_OK) != 0) {
        fprintf(stderr, "AppImage payload not found or not executable: %s\n", payload_path);
        return 1;
    }

    if (setenv("APPIMAGE_EXTRACT_AND_RUN", "1", 1) != 0) {
        perror("setenv");
        return 1;
    }

    if (getenv("QT_QPA_PLATFORM") == NULL) {
        if (setenv("QT_QPA_PLATFORM", "xcb", 1) != 0) {
            perror("setenv");
            return 1;
        }
    }

    if (getenv("XDG_SESSION_TYPE") != NULL && strcmp(getenv("XDG_SESSION_TYPE"), "wayland") == 0 && getenv("GDK_BACKEND") == NULL) {
        if (setenv("GDK_BACKEND", "x11", 1) != 0) {
            perror("setenv");
            return 1;
        }
    }

    exec_argv = calloc((size_t)argc + 1, sizeof(char *));
    if (exec_argv == NULL) {
        perror("calloc");
        return 1;
    }

    exec_argv[0] = payload_path;
    for (i = 1; i < argc; ++i) {
        exec_argv[i] = argv[i];
    }
    exec_argv[argc] = NULL;

    execv(payload_path, exec_argv);

    fprintf(stderr, "Failed to launch %s: %s\n", payload_path, strerror(errno));
    free(exec_argv);
    return 1;
}
