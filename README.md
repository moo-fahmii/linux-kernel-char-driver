# Echo Character Device Driver (Linux, x86-64 Assembly)

A character device driver at `/dev/mydev` whose logic is written
entirely in x86-64 assembly. 
C is used only for scaffolding that cannot be written in assembly on a modern kernel (struct declarations,`__randomize_layout` structs, inline functions, module macros).

Writes are stored in a 256-byte kernel buffer; reads return the
buffer contents. 
Every `open()` resets the read position, so the device is re-readable.

## Quick test

    sudo insmod mydev.ko
    echo "hello driver" | sudo tee /dev/mydev
    sudo cat /dev/mydev               #  hello driver
    sudo cat /dev/mydev               # hello driver (position reset on open)
    sudo rmmod mydev

## Files

 `mydev_main.c`  - struct declarations, `file_operations` table,
                    module metadata, C wrappers for `copy_to_user` /
                    `copy_from_user`, and 5 tiny accessors that expose
                    C-owned struct addresses to assembly
 `mydev_asm.S`   - **all driver logic**: open / read / write / release
                    callbacks and the full init / exit functions
 `Makefile`      - kbuild integration (`mydev-objs := mydev_main.o mydev_asm.o`)

Rough split: **~90% assembly, ~10% C**. All behavior is in assembly.

## Architecture

The driver implements the four file-operation callbacks:

| Callback | Assembly function | Behavior |
| `open`    | `mydev_open`     | Reset `mydev_read_pos` to 0 |
| `read`    | `mydev_read`     | Copy buffer contents to user via `copy_to_user`; clamp to remaining bytes; return 0 at EOF |
| `write`   | `mydev_write`    | Copy up to 256 bytes from user via `copy_from_user`; store length; reset read position |
| `release` | `mydev_release`  | No-op (returns 0) |

Registration is also in assembly:

`mydev_init_asm` calls `alloc_chrdev_region`  `cdev_init` 
`cdev_add`  `class_create`  `device_create`, with a chained
cleanup on error. `mydev_exit_asm` reverses all four steps.

## Why the C file exists (the C-only operations)

Four operations cannot be done in hand-written assembly on a modern
kernel, because they require compiler-level knowledge of struct
layouts that change per kernel build:

### 1. `struct cdev` is `__randomize_layout`

Field offsets in `struct cdev` are randomized at kernel build time.
No asm can know where `cdev->ops` or `cdev->owner` live. The C file
holds the `cdev` and the `file_operations` table, and exposes their
addresses to asm via accessors:

    dev_t *mydev_get_devno_addr(void) { return &mydev_devno; }

### 2. `module_init` / `module_exit` macros

These expand to version-specific section attributes and `__UNIQUE_ID`
stamps that only the C preprocessor + compiler produce correctly.

### 3. `THIS_MODULE`

References a modpost-generated symbol (`__this_module`) that asm cannot
name reliably. `mydev_set_cdev_owner()` is a 3-line C helper that
sets `cdev->owner = THIS_MODULE`.

### 4. `copy_to_user` / `copy_from_user` are inline functions

On modern kernels these are **inline**, not exported symbols. C code
calling them gets the compiler to inline a wrapper chain ending in
`_copy_to_user` or `raw_copy_to_user`. Hand-written asm that calls
`copy_to_user` fails at link time:

    ERROR: modpost: "copy_to_user" [mydev.ko] undefined!

The fix is a C wrapper:

    unsigned long mydev_copy_to_user(void __user *to, const void *from,
                                     unsigned long n) {
        return copy_to_user(to, from, n);
    }

The asm calls `mydev_copy_to_user`, a real exported symbol. The
inlining happens inside the wrapper.

**Rule of thumb:** anything in `<linux/uaccess.h>`, `<linux/atomic.h>`,
or `<linux/bitops.h>` is probably inline. If modpost says "undefined!"
for a symbol you're sure exists, add a C wrapper.

## Build

    make

Requires `build-essential` and `linux-headers-$(uname -r)`.

## Known limitations - RETHUNK mitigation

The assembly uses plain `ret` (not `RET` from `<linux/linkage.h>`),
so `objtool` emits a naked-return warning per function at build time:

    warning: objtool: mydev_open+0xd: 'naked' return found in MITIGATION_RETHUNK build
    ... (one per function)

This is documented, not fixed. Rationale:

1. It's a hardening concern, not a correctness concern. The driver
   loads, runs, and unloads correctly on a standard Ubuntu kernel.
   The Spectre v2 mitigation is bypassed for this module's call sites.
2. It's a learning exercise. The RETHUNK fix requires
   `SYM_FUNC_START` / `SYM_FUNC_END` / `RET`, which is a separate topic
   from "how does a char device driver work."

The proper fix would be:

    #include <linux/linkage.h>
    SYM_FUNC_START(mydev_open)
        ...
        RET
    SYM_FUNC_END(mydev_open)

## Notes on correctness

- **Every `copy_to_user` / `copy_from_user` return value is checked.**
  Nonzero means error (inverted from C convention - easy to get wrong).
- **Cleanup order in `mydev_exit_asm` matters:**
  `device_destroy` -> `class_destroy` -> `cdev_del` ->
  `unregister_chrdev_region`. Reversed = use-after-free warnings from
  the kernel.
- **Error-path cleanup is chained.** Each error label undoes one
  registration step and falls through to undo earlier steps.
- **Kernel taints on load** - expected for an unsigned out-of-tree
  module. `/proc/sys/kernel/tainted` will be nonzero after `insmod`.
- **`.intel_syntax noprefix`** - no libc; the module talks to the
  kernel through exported symbols directly.

## Verified behavior

    sudo insmod mydev.ko
    dmesg | tail -3
    # mydev: loaded
    # (plus expected taint warnings)

    ls -la /dev/mydev
    # crw------- 1 root root 239, 0 ... /dev/mydev   (major allocated dynamically)

    echo "hello driver" | sudo tee /dev/mydev
    sudo cat /dev/mydev               # hello driver
    sudo cat /dev/mydev               # hello driver

    echo "second message" | sudo tee /dev/mydev
    sudo cat /dev/mydev               # second message

    sudo rmmod mydev
    ls /dev/mydev                     # No such file or directory
    dmesg | tail -2
    # mydev: unloaded