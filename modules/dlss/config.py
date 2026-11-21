import os


def can_build(env, platform):
    # Optional module: only built when the user explicitly provides the NVIDIA Streamline SDK
    # (https://github.com/NVIDIAGameWorks/Streamline). The SDK is proprietary and is NOT part of this repository.
    # See modules/dlss/README.md for the license obligations and build instructions.
    if platform not in ("windows", "linuxbsd"):
        return False

    sdk_path = env.get("dlss_sdk_path", "") if hasattr(env, "get") else ""
    if not sdk_path:
        return False

    if not os.path.isfile(os.path.join(str(sdk_path), "include", "sl.h")):
        print("The 'dlss' module: 'dlss_sdk_path' does not contain 'include/sl.h'. Disabling the module.")
        return False

    if not env.get("vulkan", False):
        print("The 'dlss' module requires the Vulkan rendering driver (vulkan=yes). Disabling the module.")
        return False

    return True


def get_opts(platform):
    from SCons.Variables import PathVariable

    return [
        PathVariable(
            "dlss_sdk_path",
            "Path to a locally downloaded NVIDIA Streamline SDK (enables the optional DLSS module)",
            "",
            PathVariable.PathAccept,
        ),
    ]


def configure(env):
    pass
