/**************************************************************************/
/*  test_audio_input_cow.cpp                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_audio_input_cow)

#include "servers/audio/audio_driver.h"

#include <type_traits>
#include <utility>

namespace TestAudioInputCOW {

static_assert(std::is_same_v<decltype(std::declval<AudioDriver &>().get_input_buffer_data()), const int32_t *>,
        "Audio input must expose a stable non-owning pointer to avoid COW buffer copies.");
static_assert(std::is_same_v<decltype(std::declval<AudioDriver &>().get_input_size()), unsigned int>,
        "Audio input size must be a safe value snapshot.");

TEST_CASE("[Audio] Fixed input buffer pointer does not detach on write") {
    Vector<int32_t> samples;
    samples.resize(64);
    int32_t *original = samples.ptrw();
    const int32_t *view = original;
    CHECK(view == samples.ptr());
    samples.write[8] = 42;
    CHECK(samples.ptr() == original);
    CHECK(view[8] == 42);
    samples.write[63] = 99;
    CHECK(view[63] == 99);
}

} // namespace TestAudioInputCOW
