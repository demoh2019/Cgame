"""Godot #119985: shared Object control mutex, fewer allocations and bytes.

Compile and execute the production ObjectSignalLock and instance binding
reference methods with a minimal recursive mutex model. Native engine tests
also cover Object signals, connections and ref-counted lifetimes.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def extract_struct(code, signature):
    begin = code.index(signature)
    brace = code.index("{", begin)
    count = 0
    for i in range(brace, len(code)):
        count += (code[i] == "{") - (code[i] == "}")
        if count == 0:
            return code[begin:i+2]  # include trailing semicolon
    raise AssertionError("Unbalanced C++ struct")


def extract_method(code, signature):
    begin = code.index(signature)
    brace = code.index("{", begin)
    count = 0
    for i in range(brace, len(code)):
        count += (code[i] == "{") - (code[i] == "}")
        if count == 0:
            return code[begin:i+1]
    raise AssertionError("Unbalanced C++ function")


class ObjectMutexFastPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (ROOT / "core/object/object.cpp").read_text()
        cls.h = (ROOT / "core/object/object.h").read_text()
        cls.node = (ROOT / "scene/main/node.h").read_text()
        cls.signal_lock = extract_struct(cls.cpp, "struct ObjectSignalLock {")
        cls.ref_fn = extract_method(cls.cpp, "bool Object::_instance_binding_reference(bool p_reference)")

    def test_embedded_mutex_replaces_heap_signal_mutex(self):
        self.assertIn("mutable Mutex _control_mutex;", self.h)
        self.assertNotIn("mutable Mutex *signal_mutex", self.h)

    def test_two_mutexes_collapsed(self):
        self.assertNotIn("BinaryMutex _instance_binding_mutex;", self.h)

    def test_signal_lock_uses_control_mutex(self):
        self.assertIn("mutex1 = &p_obj1->_control_mutex;", self.signal_lock)
        self.assertIn("mutex2 = &p_obj2->_control_mutex;", self.signal_lock)

    def test_signal_order_prevents_AB_BA_deadlocks(self):
        self.assertIn("if (mutex2 < mutex1)", self.signal_lock)
        self.assertIn("SWAP(mutex1, mutex2);", self.signal_lock)

    def test_same_object_locked_only_once(self):
        self.assertIn("else if (unlikely(mutex2 == mutex1))", self.signal_lock)
        self.assertIn("mutex2 = nullptr;", self.signal_lock)

    def test_signal_mutex_is_not_heap_allocated_on_initialize(self):
        self.assertNotIn("signal_mutex = memnew(Mutex);", self.cpp)

    def test_signal_mutex_is_not_freed_on_destroy(self):
        self.assertNotIn("memdelete(signal_mutex);", self.cpp)

    def test_instance_binding_uses_control_mutex(self):
        self.assertIn("MutexLock instance_binding_lock(_control_mutex);", self.ref_fn)
        self.assertNotIn("MutexLock instance_binding_lock(_instance_binding_mutex)", self.cpp)

    def test_binding_clear_uses_control_mutex(self):
        self.assertIn("_control_mutex.lock();", self.cpp)
        self.assertIn("_control_mutex.unlock();", self.cpp)

    def test_node_has_no_signal_mutex_override(self):
        self.assertNotIn("bool _uses_signal_mutex() const override", self.node)

    def test_object_has_no_signal_mutex_hook(self):
        self.assertNotIn("bool Object::_uses_signal_mutex() const", self.cpp)

    def test_callback_false_can_prevent_reference_death(self):
        self.assertIn("if (!_instance_bindings[i].reference_callback(", self.ref_fn)
        self.assertIn("can_die = false;", self.ref_fn)

    @unittest.skipUnless(shutil.which("c++"), "C++ compiler unavailable")
    def test_compiled_production_lock_is_reentrant_and_ordered(self):
        harness = r"""
#include <algorithm>
#include <cstdint>
#include <mutex>
#include <vector>
struct Mutex {
    std::recursive_mutex actual;
    int locks = 0;
    void lock() { actual.lock(); locks++; }
    void unlock() { locks--; actual.unlock(); }
};
#define SWAP(a,b) std::swap(a,b)
#define unlikely(x) (x)
struct Object {
    friend struct ObjectSignalLock;
    mutable Mutex _control_mutex;
};
"""
        main = r"""
int main() {
    Object a, b;
    {
        ObjectSignalLock first(&a);
        if (a._control_mutex.locks != 1) return 1;
        ObjectSignalLock nested(&a);
        if (a._control_mutex.locks != 2) return 2;
        ObjectSignalLock same_pair(&a, &a);
        if (a._control_mutex.locks != 3) return 3;
        {
            ObjectSignalLock ab(&a, &b);
            ObjectSignalLock ba(&b, &a);
            if (a._control_mutex.locks != 5 || b._control_mutex.locks != 2) return 4;
        }
        if (a._control_mutex.locks != 3 || b._control_mutex.locks != 0) return 5;
    }
    if (a._control_mutex.locks != 0 || b._control_mutex.locks != 0) return 6;
    return 0;
}
"""
        self._compile_run(harness + self.signal_lock + "\n" + main)

    @unittest.skipUnless(shutil.which("c++"), "C++ compiler unavailable")
    def test_compiled_reference_callback_retains_failure_semantics(self):
        harness = r"""
#include <cstdint>
#include <mutex>
#include <vector>
struct Mutex {
    std::recursive_mutex actual;
    void lock() { actual.lock(); }
    void unlock() { actual.unlock(); }
};
template<class T> class MutexLock {
    T &mutex;
public:
    explicit MutexLock(T &value) : mutex(value) { mutex.lock(); }
    ~MutexLock() { mutex.unlock(); }
};
template<class T> MutexLock(T &) -> MutexLock<T>;
struct Object {
    mutable Mutex _control_mutex;
    struct Binding {
        using Fn = bool(*)(void*,void*,bool);
        Fn reference_callback = nullptr;
        void *token = nullptr;
        void *binding = nullptr;
    };
    Binding *_instance_bindings = nullptr;
    uint32_t _instance_binding_count = 0;
    bool _instance_binding_reference(bool);
};
int count = 0;
bool good(void*,void*,bool ref) { count++; return ref; }
bool bad(void*,void*,bool) { count++; return false; }
"""
        main = r"""
int main() {
    Object target;
    if (!target._instance_binding_reference(true)) return 1;
    Object::Binding bindings[2];
    bindings[0].reference_callback = good;
    bindings[1].reference_callback = bad;
    target._instance_bindings = bindings;
    target._instance_binding_count = 2;
    if (target._instance_binding_reference(true)) return 2;
    if (count != 2) return 3;
    bindings[1].reference_callback = good;
    if (!target._instance_binding_reference(true)) return 4;
    if (count != 4) return 5;
    return 0;
}
"""
        self._compile_run(harness + self.ref_fn + "\n" + main)

    def _compile_run(self, code):
        with tempfile.TemporaryDirectory() as directory:
            exe = str(Path(directory) / "probe")
            result = subprocess.run(["c++", "-std=c++17", "-Wall", "-Wextra",
                                     "-Werror", "-pthread", "-x", "c++", "-", "-o", exe],
                                    input=code, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([exe], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
