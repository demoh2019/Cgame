def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "CgameClientPrediction",
        "CgameDeterministicPhysics",
        "CgameNetConditioner",
        "CgamePhysicsRollback",
        "CgamePhysicsTimeline",
        "CgameRollbackDebugger",
        "CgameRollbackNetcode",
    ]


def get_doc_path():
    return "doc_classes"
