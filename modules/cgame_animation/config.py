def can_build(env, platform):
    return not env["disable_3d"]


def configure(env):
    pass


def get_doc_classes():
    return [
        "AnimationNodeMotionMatching",
        "CgameAimModifier3D",
        "CgameFacialAnimation",
        "CgameLipSync",
        "CgameLocomotionTools",
        "CgameMocapCleanup",
        "CgameMotionMatchingDatabase",
        "CgameRetargeter",
        "CgameRigIK",
        "ConstraintGraphModifier3D",
        "FootLockModifier3D",
        "FullBodyIKModifier3D",
    ]


def get_doc_path():
    return "doc_classes"
