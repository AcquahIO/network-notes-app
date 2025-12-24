import test from 'node:test';
import assert from 'node:assert/strict';
import { chunkTranscriptSegments } from '../src/services/chunking.js';
import { rankChunks } from '../src/services/retrieval.js';

test('chunkTranscriptSegments groups transcript into chunks', () => {
  const segments = [
    { start_time_seconds: 0, end_time_seconds: 10, text: 'Intro to the session.' },
    { start_time_seconds: 10, end_time_seconds: 20, text: 'We cover alignment and summaries.' },
    { start_time_seconds: 20, end_time_seconds: 30, text: 'We mention resources and study flow.' }
  ];
  const chunks = chunkTranscriptSegments(segments, { maxTokens: 10, minTokens: 1 });
  assert.ok(chunks.length >= 1);
  assert.equal(chunks[0].start_time_seconds, 0);
});

test('rankChunks returns highest similarity first', () => {
  const chunks = [
    { id: 'a', embedding: [1, 0] },
    { id: 'b', embedding: [0, 1] }
  ];
  const ranked = rankChunks({ chunks, queryEmbedding: [0.9, 0.1], limit: 2 });
  assert.equal(ranked[0].id, 'a');
});
