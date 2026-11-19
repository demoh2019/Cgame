/**************************************************************************/
/*  test_ogg_packet_sequence.cpp                                          */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_ogg_packet_sequence)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_OGG_ENABLED
#include "modules/ogg/ogg_packet_sequence.h"

namespace TestOggPacketSequence {

TEST_CASE("[OGG] Packed packet pages round-trip without changing contents") {
	Ref<OggPacketSequence> sequence;
	sequence.instantiate();
	TypedArray<Array> pages;
	Array first_page;
	PackedByteArray first_packet;
	first_packet.push_back(1);
	first_packet.push_back(2);
	first_packet.push_back(255);
	first_page.push_back(first_packet);
	pages.push_back(first_page);
	pages.push_back(Array());
	Array third_page;
	PackedByteArray third_packet;
	third_packet.push_back(100);
	third_page.push_back(third_packet);
	pages.push_back(third_page);

	sequence->set_packet_data(pages);
	TypedArray<Array> result = sequence->get_packet_data();
	REQUIRE_EQ(result.size(), 3);
	Array result_first = result[0];
	REQUIRE_EQ(result_first.size(), 1);
	PackedByteArray copy_packet = result_first[0];
	CHECK_EQ(copy_packet, first_packet);
	Array result_middle = result[1];
	CHECK(result_middle.is_empty());
	Array result_last = result[2];
	REQUIRE_EQ(result_last.size(), 1);
	PackedByteArray copy_last = result_last[0];
	CHECK_EQ(copy_last, third_packet);

	PackedInt64Array granules;
	granules.push_back(12);
	granules.push_back(12);
	granules.push_back(33);
	sequence->set_packet_granule_positions(granules);
	CHECK_EQ(sequence->get_packet_granule_positions(), granules);
	CHECK_EQ(sequence->get_final_granule_pos(), 33);
}

TEST_CASE("[OGG] Playback skips empty pages and reports packet contents") {
	Ref<OggPacketSequence> sequence;
	sequence.instantiate();
	TypedArray<Array> pages;
	Array first_page;
	PackedByteArray first_packet;
	first_packet.push_back(10);
	first_packet.push_back(20);
	first_page.push_back(first_packet);
	pages.push_back(first_page);
	pages.push_back(Array());
	Array third_page;
	PackedByteArray last_packet;
	last_packet.push_back(42);
	third_page.push_back(last_packet);
	pages.push_back(third_page);
	sequence->set_packet_data(pages);

	PackedInt64Array granules;
	granules.push_back(5);
	granules.push_back(5);
	granules.push_back(10);
	sequence->set_packet_granule_positions(granules);
	Ref<OggPacketSequencePlayback> playback = sequence->instantiate_playback();
	ogg_packet *packet = nullptr;
	REQUIRE(playback->next_ogg_packet(&packet));
	REQUIRE(packet != nullptr);
	CHECK_EQ(packet->bytes, 2);
	CHECK_EQ(packet->packet[0], 10);
	CHECK_EQ(packet->granulepos, 5);
	REQUIRE(playback->next_ogg_packet(&packet));
	CHECK_EQ(playback->get_page_number(), 2);
	CHECK_EQ(packet->bytes, 1);
	CHECK_EQ(packet->packet[0], 42);
	CHECK_EQ(packet->granulepos, 10);
	CHECK_FALSE(playback->next_ogg_packet(&packet));
}

TEST_CASE("[OGG] Replacing packet data invalidates older playbacks") {
	Ref<OggPacketSequence> sequence;
	sequence.instantiate();
	TypedArray<Array> pages;
	Array page;
	PackedByteArray packet;
	packet.push_back(1);
	page.push_back(packet);
	pages.push_back(page);
	sequence->set_packet_data(pages);
	Ref<OggPacketSequencePlayback> playback = sequence->instantiate_playback();
	sequence->set_packet_data(pages);
	ogg_packet *output = nullptr;
	ERR_PRINT_OFF;
	CHECK_FALSE(playback->next_ogg_packet(&output));
	ERR_PRINT_ON;
}
} // namespace TestOggPacketSequence
#endif // MODULE_OGG_ENABLED
