# [iSH](https://ish.app)

> ## 🚀 ARM64 Fork Notice
>
> **This repository is a fork of [ish-app/ish](https://github.com/ish-app/ish)** that adds a
> **native ARM64 guest backend** to upstream iSH's threaded-code interpreter (*Asbestos*,
> renamed from *jit* upstream in 2024 — [ish-app/ish@d375656f](https://github.com/ish-app/ish/commit/d375656f)).
> It emulates AArch64 Linux on Apple Silicon, running alongside the original x86 (i386)
> guest backend.
>
> Asbestos is **not a JIT** — it doesn't emit machine code at runtime. For each basic block
> it builds an array of pointers to pre-compiled native "gadget" functions that tail-call
> each other (the threaded-code technique Forth interpreters use). This fork's contribution
> is the **ARM64 guest backend** inside that framework: new hand-written ARM64 gadgets that
> map each AArch64 guest instruction to just a handful of host instructions — same-architecture
> dispatch, so the overhead per guest instruction is small.
>
> **Key enhancements over upstream:**
> - **Native ARM64 gadget dispatch** — same-architecture, 2-12x faster than x86 for compute
> - **48-bit virtual address space** — 4-level page table supports V8/Go/Rust runtimes
> - **Node.js 22 / npm / npx** — V8 guard pages, binary patch, `--jitless` injection
> - **Go and Rust** — large VA reservations, signal frame alignment, FUTEX_WAIT_BITSET, PMULL
> - **Full NEON + Crypto** — AES/SHA/CRC32 instructions for TLS and hashing at native-ish speed
> - **Agent integration** — `ISHShellExecutor` (Obj-C shell API), `DebugServer` (JSON-RPC over HTTP),
>   `Native Offload` (bypass emulation for selected binaries), bind mounts for host↔guest file sharing
> - **iOS-first rootfs** — Alpine 3.21 aarch64 with full `apk` ecosystem and versioned overlay patching
>
> **Performance (ARM64 vs x86, compute-heavy):** C `int_arith_2M` **12x faster**,
> Python `fib(30)` **9.2x faster**, `sum(1M)` **10.2x faster**, shell `seq+awk 100K` **7.2x faster**.
>
> **Full docs:** [README_arm64.md](README_arm64.md) · [中文版](README_arm64_zh.md) ·
> [Performance report](benchmark/BENCHMARK_PERF.md) · [Compatibility report](benchmark/BENCHMARK_COMPAT.md)
>
> ---

[![Build Status](https://github.com/ish-app/ish/actions/workflows/ci.yml/badge.svg)](https://github.com/ish-app/ish/actions)
[![goto counter](https://img.shields.io/github/search/ish-app/ish/goto.svg)](https://github.com/ish-app/ish/search?q=goto)
[![fuck counter](https://img.shields.io/github/search/ish-app/ish/fuck.svg)](https://github.com/ish-app/ish/search?q=fuck)
[![shit counter](https://img.shields.io/github/search/ish-app/ish/shit.svg)](https://github.com/ish-app/ish/search?q=shit)

<p align="center">
<a href="https://ish.app">
<img src="https://ish.app/assets/github-readme.png">
</a>
</p>

A project to get a Linux shell running on iOS, using usermode x86 emulation and syscall translation.

For the current status of the project, check the issues tab, and the commit logs.

- [App Store page](https://apps.apple.com/us/app/ish-shell/id1436902243)
- [TestFlight beta](https://testflight.apple.com/join/97i7KM8O)
- [Discord server](https://discord.gg/HFAXj44)
- [Wiki with help and tutorials](https://github.com/ish-app/ish/wiki)
- [README中文](https://github.com/ish-app/ish/blob/master/README_ZH.md) (如若未能保持最新，请提交PR以更新)

# Hacking

This project has a git submodule, make sure to clone with `--recurse-submodules` or run `git submodule update --init` after cloning.

You'll need these things to build the project:

 - Python 3
   + Meson (`pip3 install meson`)
 - Ninja
 - Clang and LLD (on mac, `brew install llvm`, on linux, `sudo apt install clang lld` or `sudo pacman -S clang lld` or whatever)
 - sqlite3 (this is so common it may already be installed on linux and is definitely already installed on mac. if not, do something like `sudo apt install libsqlite3-dev`)
 - libarchive (`brew install libarchive`, `sudo port install libarchive`, `sudo apt install libarchive-dev`) TODO: bundle this dependency

## Build for macOS (standalone ARM64 Linux shell)

This fork can build a native macOS host binary that emulates an `aarch64` Linux userspace.

### Prerequisites

- Apple Silicon Mac
- Xcode command line tools
- Python 3
- Meson
- Ninja
- sqlite3
- libarchive
- Homebrew LLVM and LLD on macOS:
  `brew install llvm lld libarchive`

### Build the host binary

```bash
git submodule update --init --recursive
meson setup build-arm64-release -Dguest_arch=arm64 --buildtype=release
ninja -C build-arm64-release
```

The resulting executable is:

```bash
./build-arm64-release/ish
```

### Build an Alpine ARM64 fakefs root

Download an Alpine `aarch64` minirootfs from the Alpine releases page, then convert it to iSH fakefs format:

```bash
mkdir -p build
curl -fL https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.7-aarch64.tar.gz \
  -o build/alpine-minirootfs-3.21.7-aarch64.tar.gz
./build-arm64-release/tools/fakefsify \
  build/alpine-minirootfs-3.21.7-aarch64.tar.gz \
  build/alpine-arm64-fakefs
```

### Run the shell

```bash
./build-arm64-release/ish -f build/alpine-arm64-fakefs /bin/sh
```

There is also a convenience launcher:

```bash
./build/run-ish-arm64.sh
```

### Notes

- The standalone macOS build now writes guest `/etc/resolv.conf` from the host's resolver config, so `apk update` and other DNS-dependent tools work out of the box.
- This is the easiest way to test the ARM64 guest backend without deploying to iOS.

## Build for iOS

For a normal Xcode build:

1. Open `app/iSH.xcconfig` and change `ROOT_BUNDLE_IDENTIFIER` to a bundle ID you control.
2. Set your Apple development team in Xcode project settings, or fill `DEVELOPMENT_TEAM` in `app/iSH.xcconfig`.
3. Open `iSH.xcodeproj` in Xcode.
4. Choose the `iSH-ARM64` scheme for the ARM64 guest build.
5. Build and run on device.

The ARM64 app target uses:

- Scheme: `iSH-ARM64`
- xcconfig: `app/AppARM64.xcconfig`
- Guest arch: `aarch64`

### Build an ad-hoc `.ipa` for sideloading / jailbroken devices

If you do not want Xcode provisioning, you can build the app and file provider unsigned, then ad-hoc sign the final bundle:

```bash
xcodebuild -project iSH.xcodeproj -scheme 'iSH-ARM64' -configuration Release \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' EXPANDED_CODE_SIGN_IDENTITY=''

xcodebuild -project iSH.xcodeproj -target 'iSHFileProvider' -configuration Release \
  build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' EXPANDED_CODE_SIGN_IDENTITY='' \
  PRODUCT_BUNDLE_IDENTIFIER='app.ish.iSH.arm64.FileProvider' \
  PRODUCT_APP_GROUP_IDENTIFIER='group.app.ish.iSH.arm64'
```

This repository already contains working ad-hoc packaging examples under `app/`:

- `app/iSH-ARM64-ad-hoc.entitlements`
- `app/iSH-ARM64-FileProvider-ad-hoc.entitlements`

The packaged output path used in local testing is:

```bash
build/iSH-ARM64-ad-hoc.ipa
```

### Files app / File Provider

- The ARM64 app depends on the `iSHFileProvider.appex` extension for Files integration.
- If the extension is not embedded, Files will not show the provider and "Browse Files" will fail.
- The ad-hoc packaged `.ipa` produced during local testing includes `PlugIns/iSHFileProvider.appex`.

## Build command line tool for testing

For the original x86 guest testing flow:

```bash
meson build
ninja -C build
```

To set up a self-contained Alpine filesystem for the original upstream-style CLI flow, download the Alpine minirootfs tarball for `i386` from the [Alpine website](https://alpinelinux.org/downloads/) and run `./tools/fakefsify`, with the minirootfs tarball as the first argument and the name of the output directory as the second argument. Then you can run things inside the Alpine filesystem with `./ish -f alpine /bin/sh`, assuming the output directory is called `alpine`. If `tools/fakefsify` doesn't exist for you in your build directory, that might be because it couldn't find libarchive on your system (see above for ways to install it.)

You can replace `ish` with `tools/ptraceomatic` to run the program in a real process and single step and compare the registers at each step. I use it for debugging. Requires 64-bit Linux 4.11 or later.

## Logging

iSH has several logging channels which can be enabled at build time. By default, all of them are disabled. To enable them:

- In Xcode: Set the `ISH_LOG` setting in iSH.xcconfig to a space-separated list of log channels.
- With Meson (command line tool for testing): Run `meson configure -Dlog="<space-separated list of log channels>"`.

Available channels:

- `strace`: The most useful channel, logs the parameters and return value of almost every system call.
- `instr`: Logs every instruction executed by the emulator. This slows things down a lot.
- `verbose`: Debug logs that don't fit into another category.
- Grep for `DEFAULT_CHANNEL` to see if more log channels have been added since this list was updated.

# A note on the interpreter

Possibly the most interesting thing I wrote as part of iSH is the interpreter. It's not quite a JIT since it doesn't target machine code. Instead it generates an array of pointers to functions called gadgets, and each gadget ends with a tailcall to the next function; like the threaded code technique used by some Forth interpreters. The result is a speedup of roughly 3-5x compared to emulation using a simpler switch dispatch.

Unfortunately, I made the decision to write nearly all of the gadgets in assembly language. This was probably a good decision with regards to performance (though I'll never know for sure), but a horrible decision with regards to readability, maintainability, and my sanity. The amount of bullshit I've had to put up with from the compiler/assembler/linker is insane. It's like there's a demon in there that makes sure my code is sufficiently deformed, and if not, makes up stupid reasons why it shouldn't compile. In order to stay sane while writing this code, I've had to ignore best practices in code structure and naming. You'll find macros and variables with such descriptive names as `ss` and `s` and `a`. Assembler macros nested beyond belief. And to top it off, there are almost no comments.

So a warning: Long-term exposure to this code may cause loss of sanity, nightmares about GAS macros and linker errors, or any number of other debilitating side effects. This code is known to the State of California to cause cancer, birth defects, and reproductive harm.
