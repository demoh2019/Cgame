import os


def can_build(env, platform):
    # Optional module: only built when the user explicitly provides the Intel XeSS SDK
    # (https://github.com/intel/xess). The SDK is licensed separately by Intel and is NOT part of this repository.
    # See modules/xess/README.md for the license obligations and build instructions.
    if platform not in ("windows", "linuxbsd"):
        return False

    sdk_path = env.get("xess_sdk_path", "") if hasattr(env, "get") else ""
    if not sdk_path:
        return False

    if not os.path.isfile(os.path.join(str(sdk_path), "inc", "xess", "xess_vk.h")):
        print("The 'xess' module: 'xess_sdk_path' does not contain 'inc/xess/xess_vk.h'. Disabling the module.")
        return False

    if not env.get("vulkan", False):
        print("The 'xess' module requires the Vulkan rendering driver (vulkan=yes). Disabling the module.")
        return False

    return True


def get_opts(platform):
    from SCons.Variables import PathVariable

    return [
        PathVariable(
            "xess_sdk_path",
            "Path to a locally downloaded Intel XeSS SDK (enables the optional XeSS module)",
            "",
            PathVariable.PathAccept,
        ),
    ]


def configure(env):
    pass
