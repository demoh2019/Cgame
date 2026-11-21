/**************************************************************************/
/*  cgame_ownership_leases.cpp                                            */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "cgame_ownership_leases.h"

bool CgameFencedStore::write(const String &p_key, int p_token, const Variant &p_value) {
	if (p_token < int(max_token.get(p_key, 0))) {
		rejected++;
		return false;
	}
	max_token[p_key] = p_token;
	values[p_key] = p_value;
	return true;
}

Variant CgameFencedStore::read(const String &p_key) const {
	return values.get(p_key, Variant());
}

void CgameFencedStore::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameFencedStore, Variant::DICTIONARY, max_token)
	CGAME_BIND_PROPERTY(CgameFencedStore, Variant::DICTIONARY, values)
	CGAME_BIND_PROPERTY(CgameFencedStore, Variant::INT, rejected)

	ClassDB::bind_method(D_METHOD("write", "key", "token", "value"), &CgameFencedStore::write);
	ClassDB::bind_method(D_METHOD("read", "key"), &CgameFencedStore::read);
}

// Grants (or re-confirms) the lease: {"ok", "token", "expires"}. A different holder is refused
// until the current lease has expired; a new grant always gets a strictly higher token.
Dictionary CgameOwnershipLeases::acquire(const String &p_key, const String &p_holder, double p_now, double p_ttl) {
	Dictionary res;
	if (leases.has(p_key)) {
		Dictionary cur = leases[p_key];
		if (double(cur["expires"]) > p_now) {
			if (String(cur["holder"]) == p_holder) {
				cur["expires"] = p_now + p_ttl;
				res["ok"] = true;
				res["token"] = int(cur["token"]);
				res["expires"] = p_now + p_ttl;
				return res;
			}
			res["ok"] = false;
			res["token"] = 0;
			res["expires"] = double(cur["expires"]);
			return res;
		}
	}
	const int token = int(tokens.get(p_key, 0)) + 1;
	tokens[p_key] = token;
	Dictionary lease;
	lease["holder"] = p_holder;
	lease["token"] = token;
	lease["expires"] = p_now + p_ttl;
	leases[p_key] = lease;
	res["ok"] = true;
	res["token"] = token;
	res["expires"] = p_now + p_ttl;
	return res;
}

// Extends the lease. Refused once expired (the holder must re-acquire and get a new token) or
// when the token or holder does not match the current grant.
bool CgameOwnershipLeases::renew(const String &p_key, const String &p_holder, int p_token, double p_now, double p_ttl) {
	if (!leases.has(p_key)) {
		return false;
	}
	Dictionary cur = leases[p_key];
	if (String(cur["holder"]) != p_holder || int(cur["token"]) != p_token || double(cur["expires"]) <= p_now) {
		return false;
	}
	cur["expires"] = p_now + p_ttl;
	return true;
}

bool CgameOwnershipLeases::release(const String &p_key, const String &p_holder, int p_token) {
	if (!leases.has(p_key)) {
		return false;
	}
	Dictionary cur = leases[p_key];
	if (String(cur["holder"]) != p_holder || int(cur["token"]) != p_token) {
		return false;
	}
	leases.erase(p_key);
	return true;
}

// Current holder, or "" when free or expired.
String CgameOwnershipLeases::holder_of(const String &p_key, double p_now) const {
	if (!leases.has(p_key)) {
		return "";
	}
	Dictionary cur = leases[p_key];
	if (double(cur["expires"]) <= p_now) {
		return "";
	}
	return String(cur["holder"]);
}

int CgameOwnershipLeases::token_of(const String &p_key) const {
	return int(tokens.get(p_key, 0));
}

bool CgameOwnershipLeases::is_valid(const String &p_key, const String &p_holder, int p_token, double p_now) const {
	if (!leases.has(p_key) || holder_of(p_key, p_now) != p_holder) {
		return false;
	}
	Dictionary cur = leases[p_key];
	return int(cur["token"]) == p_token;
}

// Holder-side check with a drift allowance: stop acting `drift` before the server-side expiry.
bool CgameOwnershipLeases::client_valid(double p_expires, double p_now, double p_drift) {
	return p_now < p_expires - p_drift;
}

// Drops expired leases and returns their keys (tokens are kept so the next grant is higher).
Array CgameOwnershipLeases::reap(double p_now) {
	Array gone;
	Array keys = leases.keys();
	for (int i = 0; i < keys.size(); i++) {
		Dictionary cur = leases[keys[i]];
		if (double(cur["expires"]) <= p_now) {
			gone.push_back(keys[i]);
		}
	}
	for (int i = 0; i < gone.size(); i++) {
		leases.erase(gone[i]);
	}
	return gone;
}

void CgameOwnershipLeases::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameOwnershipLeases, Variant::DICTIONARY, leases)

	ClassDB::bind_method(D_METHOD("acquire", "key", "holder", "now", "ttl"), &CgameOwnershipLeases::acquire);
	ClassDB::bind_method(D_METHOD("renew", "key", "holder", "token", "now", "ttl"), &CgameOwnershipLeases::renew);
	ClassDB::bind_method(D_METHOD("release", "key", "holder", "token"), &CgameOwnershipLeases::release);
	ClassDB::bind_method(D_METHOD("holder_of", "key", "now"), &CgameOwnershipLeases::holder_of);
	ClassDB::bind_method(D_METHOD("token_of", "key"), &CgameOwnershipLeases::token_of);
	ClassDB::bind_method(D_METHOD("is_valid", "key", "holder", "token", "now"), &CgameOwnershipLeases::is_valid);
	ClassDB::bind_static_method("CgameOwnershipLeases", D_METHOD("client_valid", "expires", "now", "drift"), &CgameOwnershipLeases::client_valid);
	ClassDB::bind_method(D_METHOD("reap", "now"), &CgameOwnershipLeases::reap);
}
