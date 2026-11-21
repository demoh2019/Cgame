def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "CgameClusterSimulator",
        "CgameFencedStore",
        "CgameGuildSync",
        "CgameItemLedger",
        "CgameLagCompensation",
        "CgameOwnershipLeases",
        "CgamePartyMigration",
        "CgameReplayRecorder",
        "CgameSaveMigrations",
        "CgameTradeJournal",
        "CgameTransactionCoordinator",
        "CgameWorldSharding",
    ]


def get_doc_path():
    return "doc_classes"
