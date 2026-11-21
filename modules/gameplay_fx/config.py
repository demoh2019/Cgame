def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "SoundConcurrency",
        "SoundConcurrencyManager",
        "SoundPropagation",
        "RadialForceField3D",
        "GameplayEffectTimeline",
        "GameplayAttributeSet",
        "GameplayCooldownTracker",
        "GameplayCueQueue",
        "AudioDuckMix",
        "AudioMixSnapshotController",
    ]


def get_doc_path():
    return "doc_classes"
