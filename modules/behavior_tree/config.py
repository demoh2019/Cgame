def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "BehaviorTreeTask",
        "BehaviorTreeComposite",
        "BehaviorTreeSequence",
        "BehaviorTreeSelector",
        "BehaviorTreeReactiveSequence",
        "BehaviorTreeReactiveSelector",
        "BehaviorTreeInverter",
        "BehaviorTreeBlackboardCheck",
        "BehaviorTreeBlackboardCompare",
        "BehaviorTreeBlackboardSet",
        "BehaviorTreeWait",
        "BehaviorTreeRunner",
        "AIVisualSensor2D",
        "AIHearingSensor2D",
        "AIStimulusHistory2D",
        "AIExecutionProfiler",
        "AISimulationLOD2D",
        "AIUpdateScheduler",
        "AIThreatTable2D",
    ]


def get_doc_path():
    return "doc_classes"
