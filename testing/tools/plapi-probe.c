#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

/*
 * ISmmPlugin vtable structure in Metamod:Source C++ interface:
 * vtable[0]: GetApiVersion
 */
typedef int (*GetApiVersionFn)(void *self);

typedef void *(*CreateInterfaceFn)(const char *name, int *code);

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <path_to_so> [interface_name]\n", argv[0]);
        return 1;
    }

    const char *so_path = argv[1];
    const char *iface_name = (argc >= 3) ? argv[2] : "ISmmPlugin";

    void *handle = dlopen(so_path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "dlopen failed for %s: %s\n", so_path, dlerror());
        return 2;
    }

    CreateInterfaceFn create_iface = (CreateInterfaceFn)dlsym(handle, "CreateInterface_MMS");
    if (!create_iface) {
        create_iface = (CreateInterfaceFn)dlsym(handle, "CreateInterface");
    }

    if (!create_iface) {
        fprintf(stderr, "CreateInterface / CreateInterface_MMS export not found in %s\n", so_path);
        dlclose(handle);
        return 3;
    }

    int ret_code = 0;
    void *iface = create_iface(iface_name, &ret_code);

    if (!iface) {
        fprintf(stderr, "CreateInterface returned NULL for %s\n", so_path);
        dlclose(handle);
        return 4;
    }

    /* Dereference vtable pointer (first entry in C++ object layout) */
    void **vtable = *(void ***)iface;
    if (!vtable || !vtable[0]) {
        fprintf(stderr, "Invalid vtable for %s\n", so_path);
        dlclose(handle);
        return 5;
    }

    GetApiVersionFn get_api_ver = (GetApiVersionFn)vtable[0];
    int api_ver = get_api_ver(iface);

    printf("PLAPI:%d\n", api_ver);
    /* Flush before dlclose: module destructors may abort and stdout is a pipe. */
    fflush(stdout);

    dlclose(handle);
    return 0;
}
