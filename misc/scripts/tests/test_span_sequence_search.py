#!/usr/bin/env python3
"""Compile the real Span header with minimal engine stubs and randomized tests."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
STUB = r"""
#pragma once
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <type_traits>
#define _FORCE_INLINE_ inline
#define DEV_ASSERT(x) assert(x)
#define CRASH_COND(x) assert(!(x))
template<class T> struct is_zero_constructible {};
template<class T> struct Comparator {
 bool operator()(const T &a,const T &b) const { return a < b; }
};
"""
CPP = r"""
#include "core/templates/span.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <random>
#include <vector>

int64_t forward(const std::vector<uint8_t>&h,const std::vector<uint8_t>&n,uint64_t from){
 if(from>h.size()||n.size()>h.size()-from) return -1;
 if(n.empty()) return from;
 for(uint64_t i=from;i<=h.size()-n.size();++i)
  if(std::equal(n.begin(),n.end(),h.begin()+i)) return i;
 return -1;
}
int64_t backward(const std::vector<uint8_t>&h,const std::vector<uint8_t>&n,uint64_t from){
 if(from>h.size()||n.size()>h.size()-from) return -1;
 if(n.empty()) return from;
 for(uint64_t i=from+1;i>0;){--i;
  if(std::equal(n.begin(),n.end(),h.begin()+i)) return i;
 }
 return -1;
}
int64_t baseline(const Span<uint8_t>&h,const Span<uint8_t>&n){
 if(n.size()>h.size())return -1;
 if(n.is_empty())return 0;
 for(uint64_t i=0;i<=h.size()-n.size();++i)
  if(std::memcmp(h.ptr()+i,n.ptr(),n.size())==0)return i;
 return -1;
}
struct NeverEqual {
 bool operator!=(const NeverEqual &) const { return true; }
};
int main(){
 // Identity equality only applies to fundamental types and must not hide
 // custom non-reflexive element comparisons.
 std::vector<uint8_t> identity(1024,42), copy=identity;
 const Span<uint8_t> a(identity.data(),identity.size());
 const Span<uint8_t> b(identity.data(),identity.size());
 const Span<uint8_t> c(copy.data(),copy.size());
 if(!(a==b) || !(a==c))return 5;
 copy[1023]=77;
 if(a==c || !(a==b))return 6;
 NeverEqual strange;
 const Span<NeverEqual> non_reflexive(&strange,1);
 if(non_reflexive==non_reflexive)return 7;
 std::mt19937 rng(912371);
 for(int trial=0;trial<2400;++trial){
  std::vector<uint8_t> h(rng()%160),n(rng()%45);
  for(auto &v:h)v=rng()%5;
  for(auto &v:n)v=rng()%5;
  Span<uint8_t> hs(h.data(),h.size()),ns(n.data(),n.size());
  for(uint64_t from=0;from<=h.size()+2;++from){
   if(hs.find_sequence(ns,from)!=forward(h,n,from))return 1;
   if(hs.rfind_sequence(ns,from)!=backward(h,n,from))return 2;
  }
  const int64_t expect=n.size()>h.size()?-1:backward(h,n,h.size()-n.size());
  if(hs.rfind_sequence(ns)!=expect)return 3;
  // Compare runtime memchr fast paths against the standard linear search.
  for(uint64_t from=0;from<=h.size()+2;from+=std::max<uint64_t>(1,h.size()/8+1)){
   for(int b=0;b<256;b+=7){
    const int64_t expected=from>=h.size()?-1:[&](){
     auto it=std::find(h.begin()+from,h.end(),uint8_t(b));
     return it==h.end()?int64_t(-1):int64_t(it-h.begin());
    }();
    if(hs.find(uint8_t(b),from)!=expected)return 4;
   }
  }
 }
 // Exhaustive runtime byte counts on the real Span implementation.
 static constexpr uint8_t constexpr_bytes[] = {0, 1, 0, 2, 0};
 static constexpr Span<uint8_t> constexpr_span(constexpr_bytes);
 static_assert(constexpr_span.count(uint8_t(0)) == 3);
 static_assert(constexpr_span.count(uint8_t(2)) == 1);
 static_assert(Span<uint8_t>().count(uint8_t(0)) == 0);
 std::vector<uint8_t> count_data(1033);
 for(auto &value : count_data)value=uint8_t(rng()%256);
 const uint64_t lengths[]={0,1,2,7,8,9,15,16,31,32,33,63,64,65,71,127,128,129,255,256,257,511,512,513,1024};
 for(int offset=0;offset<8;offset++){
  for(uint64_t length:lengths){
   Span<uint8_t> values(count_data.data()+offset,length);
   for(int needle=0;needle<256;needle++){
    const uint64_t expected=std::count(count_data.begin()+offset,count_data.begin()+offset+length,uint8_t(needle));
    if(values.count(uint8_t(needle))!=expected)return 8;
   }
  }
 }
 int8_t signed_values[130];
 for(int i=0;i<130;i++)signed_values[i]=int8_t(i*17-128);
 Span<int8_t> signed_span(signed_values);
 for(int needle=-128;needle<128;needle++){
  uint64_t expected=0;
  for(int8_t value:signed_values)expected+=(value==int8_t(needle));
  if(signed_span.count(int8_t(needle))!=expected)return 9;
 }
 std::vector<uint8_t> big(2*1024*1024,0);
 const uint8_t needle[]={255,32,48,64,80,96,112,128};
 Span<uint8_t> hs(big.data(),big.size()),ns(needle);
 volatile int64_t sink=0;
 auto run=[&](bool fast){
  const auto start=std::chrono::steady_clock::now();
  for(int i=0;i<24;++i)sink+=fast?hs.find_sequence(ns):baseline(hs,ns);
  return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
 };
 const double base=run(false),fast=run(true);
 std::cout << "2400 randomized Span searches and exhaustive byte count checks passed; baseline ms=" << base << "; fast ms=" << fast << "; sink=" << sink << "\n";
}
"""

def main():
    with tempfile.TemporaryDirectory(prefix="godot-span-") as tmp:
        path = Path(tmp)
        (path / "core/error").mkdir(parents=True)
        (path / "core/typedefs.h").write_text(STUB)
        (path / "core/error/error_macros.h").write_text("#pragma once\n")
        (path / "test.cpp").write_text(CPP)
        binary = path / "test"
        subprocess.run([os.environ.get("CXX", "c++"), "-std=c++17", "-O2", "-Wall", "-Wextra", "-I", str(path), "-I", str(ROOT), str(path / "test.cpp"), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

if __name__ == "__main__":
    main()
