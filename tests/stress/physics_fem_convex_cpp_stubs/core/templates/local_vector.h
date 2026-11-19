// Test-only compact API emulation; production engine always uses Godot LocalVector.
#pragma once
#include <cstdint>
#include <utility>
#include <vector>

template <typename T>
class LocalVector {
	std::vector<T> data;
public:
	uint32_t size() const { return uint32_t(data.size()); }
	T *ptr() { return data.data(); }
	const T *ptr() const { return data.data(); }
	bool is_empty() const { return data.empty(); }
	void reset() { data.clear(); data.shrink_to_fit(); }
	void reserve(uint32_t capacity) { data.reserve(capacity); }
	void resize(uint32_t amount) { data.resize(amount); }
	void push_back(const T &v) { data.push_back(v); }
	void push_back(T &&v) { data.push_back(std::move(v)); }
	T &operator[](uint32_t i) { return data[i]; }
	const T &operator[](uint32_t i) const { return data[i]; }
	auto begin() { return data.begin(); }
	auto end() { return data.end(); }
	auto begin() const { return data.begin(); }
	auto end() const { return data.end(); }
};
