//
//  main.m
//  iSH
//
//  Created by Theodore Dubois on 10/17/17.
//

#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#import "AppDelegate.h"
#import "ExceptionExfiltrator.h"

#if defined(GUEST_ARM64) && defined(__aarch64__) && !TARGET_OS_SIMULATOR
#include <spawn.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "jit/guest-arm64/jit.h"

extern char **environ;
extern int ptrace(int request, pid_t pid, caddr_t addr, int data);
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator)
    __attribute__((weak_import));
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task,
        CFStringRef entitlement, CFErrorRef *error)
    __attribute__((weak_import));
#define ISH_PT_TRACE_ME 0
#define ISH_PT_DETACH 11

static BOOL iSHHasBooleanEntitlement(NSString *key) {
    if (SecTaskCreateFromSelf == NULL || SecTaskCopyValueForEntitlement == NULL)
        return NO;
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    if (task == NULL)
        return NO;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, (__bridge CFStringRef) key, NULL);
    CFRelease(task);
    if (value == NULL)
        return NO;
    BOOL result = CFGetTypeID(value) != CFBooleanGetTypeID() ||
            CFBooleanGetValue((CFBooleanRef) value);
    CFRelease(value);
    return result;
}

static void iSHTryEnableJITWithTraceMe(const char *path) {
    if (arm64_jit_process_has_jit())
        return;
    if (!iSHHasBooleanEntitlement(@"com.apple.private.security.no-sandbox"))
        return;

    pid_t pid = 0;
    char *const childArgv[] = {(char *) path, (char *) "--ish-arm64-jit-trace-me", NULL};
    int ret = posix_spawnp(&pid, path, NULL, NULL, childArgv, environ);
    if (ret != 0)
        return;
    waitpid(pid, NULL, WUNTRACED);
    ptrace(ISH_PT_DETACH, pid, NULL, 0);
    kill(pid, SIGTERM);
    waitpid(pid, NULL, 0);
}
#endif

int main(int argc, char * argv[]) {
#if defined(GUEST_ARM64) && defined(__aarch64__) && !TARGET_OS_SIMULATOR
    if (argc == 2 && strcmp(argv[1], "--ish-arm64-jit-trace-me") == 0)
        return ptrace(ISH_PT_TRACE_ME, 0, NULL, 0);
    iSHTryEnableJITWithTraceMe(argv[0]);
#endif
    NSSetUncaughtExceptionHandler(iSHExceptionHandler);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
