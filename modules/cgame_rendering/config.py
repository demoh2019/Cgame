def can_build(env, platform):
    return not env["disable_3d"]


def configure(env):
    pass


def get_doc_classes():
    return [
        "CgameImpostorBaker",
        "ImpostorField3D",
        "CgameShaderWarmup",
        "CgameFoveatedShading",
        "CgameFramePacing",
        "CgameHDROutput",
        "CgameAreaLights",
        "CgameVRAMBudget",
        "CgameGPUResourceReport",
        "CgameRTEffect",
        "CgameInstanceCulling",
    ]


def get_doc_path():
    return "doc_classes"
