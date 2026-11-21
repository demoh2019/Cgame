/**************************************************************************/
/*  test_world_streamer_chunk_cache.cpp                                    */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_world_streamer_chunk_cache)

#include "scene/main/world_streamer.h"

namespace TestWorldStreamerChunkCache {

TEST_CASE("[WorldStreamer] Procedural chunk cache is opt-in and bounded") {
	WorldStreamer *streamer = memnew(WorldStreamer);
	CHECK(streamer->get_max_cached_chunks() == 0);
	CHECK(streamer->get_cached_chunk_count() == 0);
	CHECK(streamer->get_chunk_cache_hit_count() == 0);
	CHECK(streamer->get_chunk_cache_eviction_count() == 0);

	streamer->set_max_cached_chunks(500);
	CHECK(streamer->get_max_cached_chunks() == 16);
	streamer->set_max_cached_chunks(-1);
	CHECK(streamer->get_max_cached_chunks() == 0);
	CHECK(streamer->get_cached_chunk_count() == 0);
	streamer->clear_cached_chunks();
	CHECK(streamer->get_chunk_cache_hit_count() == 0);
	CHECK(streamer->get_chunk_cache_eviction_count() == 0);
	memdelete(streamer);
}

} // namespace TestWorldStreamerChunkCache
