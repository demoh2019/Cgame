def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "CgameAssetConflicts",
        "CgameDesktopPlatformBackend",
        "CgameGPUMatrixDB",
        "CgameGPUSettingsDB",
        "CgameLatencyProbe",
        "CgameMockPlatformBackend",
        "CgamePerfStats",
        "CgamePlatformBackend",
        "CgamePlatformServices",
        "CgameSafeArea",
        "CgameSceneCRDT",
        "CgameThermalGovernor",
    ]


def get_doc_path():
    return "doc_classes"
