#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>

typedef void *(*CreateInterfaceFn)(const char *name, int *ret);
typedef int (*GetApiVersionFn)(void *self);

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <path_to_so>\n", argv[0]);
        return 1;
    }

    const char *so_path = argv[1];
    void *handle = dlopen(so_path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "dlopen failed for %s: %s\n", so_path, dlerror());
        return 1;
    }

    CreateInterfaceFn fn = (CreateInterfaceFn)dlsym(handle, "CreateInterface_MMS");
    if (!fn) {
        fn = (CreateInterfaceFn)dlsym(handle, "CreateInterface");
    }

    if (!fn) {
        fprintf(stderr, "No CreateInterface_MMS or CreateInterface symbol in %s\n", so_path);
        dlclose(handle);
        return 1;
    }

    int status = 0;
    void *pPlugin = fn("ISmmPlugin", &status);
    if (!pPlugin) {
        fprintf(stderr, "CreateInterface(\"ISmmPlugin\") returned NULL in %s (status=%d)\n", so_path, status);
        dlclose(handle);
        return 1;
    }

    void **vtable = *(void ***)pPlugin;
    if (!vtable || !vtable[0]) {
        fprintf(stderr, "Invalid vtable for ISmmPlugin in %s\n", so_path);
        dlclose(handle);
        return 1;
    }

    GetApiVersionFn get_api_version = (GetApiVersionFn)vtable[0];
    int plapi = get_api_version(pPlugin);
    printf("PLAPI: %d\n", plapi);

    dlclose(handle);
    return 0;
}
