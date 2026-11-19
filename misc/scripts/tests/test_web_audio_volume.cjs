#!/usr/bin/env node
// Execute the actual engine's WebAudio mixer against counting fake AudioParams.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const data = fs.readFileSync(path.join(__dirname, '../../../platform/web/js/libs/library_godot_audio.js'), 'utf8');
const begin = data.indexOf('\tfunction createVolumeMixer(bus) {');
const end = data.indexOf('\n\t/**\n\t * @param {string} streamId', begin);
assert(begin >= 0 && end > begin, 'mixer function located in production source');
const snippet = data.slice(begin, end);

let writes = 0;
let errors = 0;
const channels = [];
function makeGain() {
  let value = 1;
  const result = {
    gain: {
      get value() { return value; },
      set value(v) { writes++; value = v; },
    },
    connect() { return this; },
    disconnect() {},
  };
  channels.push(result);
  return result;
}
const ctx = {
  createChannelSplitter() { return { connect(ch) { return ch; }, disconnect() {} }; },
  createChannelMerger() { return { connect() {}, disconnect() {} }; },
  createGain: makeGain,
};
const enums = { CHANNEL_L: 0, CHANNEL_R: 1, CHANNEL_SL: 2,
  CHANNEL_SR: 3, CHANNEL_C: 4, CHANNEL_LFE: 5 };
const fake = {
  ctx, NUMBER_OF_WEB_CHANNELS: 6, MAX_VOLUME_CHANNELS: 6,
  WebChannel: enums, GodotChannel: enums,
  getBus() { return { getInputNode() { return {}; } }; },
  GodotRuntime: { error() { errors++; } },
};
const createVolumeMixer = vm.runInNewContext(snippet + '\ncreateVolumeMixer;', fake);
const mixer = createVolumeMixer(0);
const data1 = new Float32Array([0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
mixer.setVolume(data1);
assert.equal(writes, 6, 'initial channel values applied');
for (let i = 0; i < 200; i++) mixer.setVolume(data1);
assert.equal(writes, 6, 'repeated frames perform no AudioParam writes');
data1[3] = 0.7;
mixer.setVolume(data1);
assert.equal(writes, 7, 'changing one channel writes only once');
assert.equal(channels[3].gain.value, data1[3]);
mixer.setVolume(new Float32Array(3));
assert.equal(errors, 1, 'wrong channel count still signals an error');
assert.equal(writes, 7, 'invalid volume input never writes');
mixer.clear();
console.log('WebAudio: initial 6 writes; 200 identical updates 0 writes; one channel change 1 write');
