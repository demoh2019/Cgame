var evaluation_count: int = 0

func rhs(value: bool) -> bool:
	evaluation_count += 1
	return value

func test():
	var false_flag: bool = false
	var true_flag: bool = true

	evaluation_count = 0
	if false_flag and rhs(true):
		print("unexpected and branch")
	print("and skips rhs: ", "SUCCESS" if evaluation_count == 0 else "FAIL")

	evaluation_count = 0
	if true_flag or rhs(false):
		pass
	print("or skips rhs: ", "SUCCESS" if evaluation_count == 0 else "FAIL")

	evaluation_count = 0
	if true_flag and rhs(true):
		pass
	print("and evaluates rhs: ", "SUCCESS" if evaluation_count == 1 else "FAIL")

	evaluation_count = 0
	if false_flag or rhs(true):
		pass
	print("or evaluates rhs: ", "SUCCESS" if evaluation_count == 1 else "FAIL")

	evaluation_count = 0
	if false_flag and (true_flag or rhs(true)):
		print("unexpected nested branch")
	print("nested skip: ", "SUCCESS" if evaluation_count == 0 else "FAIL")

	evaluation_count = 0
	if (true_flag or rhs(false)) and rhs(true):
		pass
	print("nested evaluate once: ", "SUCCESS" if evaluation_count == 1 else "FAIL")
