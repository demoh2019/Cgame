"""Source contracts for small Vulkan VMA pools and allocation retries."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "drivers/vulkan/rendering_device_driver_vulkan.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "drivers/vulkan/rendering_device_driver_vulkan.h").read_text(encoding="utf-8")

class VulkanSmallPoolContracts(unittest.TestCase):
    def test_fixed_small_pool_storage(self):
        self.assertIn("VmaPool small_allocs_pools[VK_MAX_MEMORY_TYPES]{};", HEADER)
        self.assertNotIn("HashMap<uint32_t, VmaPool> small_allocs_pools", HEADER)

    def test_no_mutable_map_lookup_on_allocation_path(self):
        self.assertNotIn("_find_or_create_small_allocs_pool", CPP + HEADER)
        self.assertIn("alloc_create_info.pool = small_allocs_pools[mem_type_index];", CPP)

    def test_pool_init_runs_at_allocator_start(self):
        init = CPP[CPP.index("Error RenderingDeviceDriverVulkan::_initialize_allocator()"):
                   CPP.index("Error RenderingDeviceDriverVulkan::_initialize_pipeline_cache()")]
        self.assertIn("vmaCreatePool(allocator, &pci, &pool);", init)
        self.assertIn("memory_properties->memoryTypeCount", init)

    def test_unsupported_memory_type_can_have_null_pool(self):
        self.assertIn("if (err == VK_ERROR_FEATURE_NOT_PRESENT)", CPP)

    def test_buffer_creation_retries_outside_pool(self):
        self.assertGreaterEqual(CPP.count("err = vmaCreateBuffer("), 2)
        self.assertGreaterEqual(CPP.count("err = vmaAllocateMemoryForBuffer("), 2)

    def test_texture_creation_retries_outside_pool(self):
        self.assertGreaterEqual(CPP.count("err = vmaCreateImage("), 2)
        self.assertGreaterEqual(CPP.count("err = vmaAllocateMemoryForImage("), 2)

    def test_pool_failures_are_only_retried_with_a_pool(self):
        self.assertGreaterEqual(CPP.count("if (err && alloc_create_info.pool != VK_NULL_HANDLE)"), 4)
        self.assertGreaterEqual(CPP.count("alloc_create_info.pool = VK_NULL_HANDLE;"), 4)

    def test_host_visible_memory_fallback(self):
        self.assertIn("requiredFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT", CPP)
        self.assertIn("preferredFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT", CPP)

    def test_null_pools_are_skipped_on_teardown(self):
        dtor = CPP[CPP.index("RenderingDeviceDriverVulkan::~RenderingDeviceDriverVulkan()"):]
        self.assertIn("if (pool != VK_NULL_HANDLE)", dtor)
        self.assertLess(dtor.index("vmaDestroyPool(allocator, pool)"),
                        dtor.index("vmaDestroyAllocator(allocator)"))

    def test_buffer_image_errors_are_preserved(self):
        self.assertIn("Can't create buffer of size:", CPP)
        self.assertIn("Couldn't create Vulkan image", CPP)


if __name__ == "__main__":
    unittest.main()
