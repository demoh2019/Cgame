@tool
extends RefCounted

# Fail-closed validation for AI endpoints. This is not an SSRF sandbox:
# users deliberately choose remote HTTPS endpoints, but HTTP must be limited
# to an exact loopback host (not merely a matching string prefix).
const LOOPBACK_HOSTS := ["localhost", "127.0.0.1", "::1"]


static func is_allowed(endpoint: String) -> bool:
	if endpoint.is_empty() or endpoint != endpoint.strip_edges():
		return false
	# Reject credentials, fragments, backslashes, whitespace, and control
	# characters, including in the path/query, before sending authorization.
	if endpoint.contains("@") or endpoint.contains("#") or endpoint.contains("\\"):
		return false
	for i in range(endpoint.length()):
		var character := endpoint.unicode_at(i)
		if character <= 32 or character >= 127:
			return false

	var https := endpoint.begins_with("https://")
	var http := endpoint.begins_with("http://")
	if not https and not http:
		return false

	var remainder := endpoint.substr(8 if https else 7)
	var authority_end := remainder.length()
	for separator in ["/", "?"]:
		var index := remainder.find(separator)
		if index >= 0:
			authority_end = mini(authority_end, index)

	var authority := remainder.substr(0, authority_end)
	if authority.is_empty():
		return false

	var host := ""
	var port := ""
	if authority.begins_with("["):
		var closing := authority.find("]")
		if closing <= 1:
			return false
		host = authority.substr(1, closing - 1).to_lower()
		var suffix := authority.substr(closing + 1)
		if not suffix.is_empty():
			if not suffix.begins_with(":"):
				return false
			port = suffix.substr(1)
			if port.is_empty():
				return false
		if not _valid_ipv6_literal(host):
			return false
	else:
		var parts := authority.split(":", true)
		if parts.size() > 2:
			return false
		host = parts[0].to_lower()
		if not _valid_hostname(host):
			return false
		if parts.size() == 2:
			port = parts[1]
			if port.is_empty():
				return false

	if not port.is_empty():
		if port.length() > 5:
			return false
		for i in range(port.length()):
			var c := port.unicode_at(i)
			if c < 48 or c > 57:
				return false
		var port_number := port.to_int()
		if port_number < 1 or port_number > 65535:
			return false

	return https or LOOPBACK_HOSTS.has(host)


static func is_valid_bearer_token(token: String) -> bool:
	if token.length() > 4096:
		return false
	# A blank token is valid for providers that need no API key.
	for i in range(token.length()):
		var c := token.unicode_at(i)
		if c <= 32 or c >= 127:
			return false
	return true


static func _valid_hostname(host: String) -> bool:
	if host.is_empty() or host.length() > 253:
		return false
	for label in host.split(".", true):
		if label.is_empty() or label.length() > 63:
			return false
		for i in range(label.length()):
			var c := label.unicode_at(i)
			var letter := (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
			var digit := c >= 48 and c <= 57
			var hyphen := c == 45 and i > 0 and i < label.length() - 1
			if not letter and not digit and not hyphen:
				return false
	return true


static func _valid_ipv6_literal(host: String) -> bool:
	# Full IPv6 validation remains the job of HTTPRequest. Reject non-hex
	# characters so an authority cannot smuggle userinfo or a new hostname.
	if host.count(":") < 2:
		return false
	for i in range(host.length()):
		var c := host.unicode_at(i)
		var hex_digit := (c >= 48 and c <= 57) or (c >= 97 and c <= 102)
		if not hex_digit and c != 58:
			return false
	return true
