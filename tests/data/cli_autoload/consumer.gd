extends RefCounted

static func is_ready() -> bool:
	return TestAutoload != null and TestAutoload.answer == 42
