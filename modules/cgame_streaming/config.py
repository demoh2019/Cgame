def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "WorldPartitionBake",
        "OriginRebasing",
        "StreamRequestQueue",
        "StreamReadinessGate",
        "StreamReplication",
        "StreamReplicationClient",
        "NavMeshStitching",
        "NavMeshCarving",
        "SHLighting",
        "ProbeVolume",
        "VirtualTexturePageCache",
        "VirtualShadowPages",
    ]


def get_doc_path():
    return "doc_classes"
