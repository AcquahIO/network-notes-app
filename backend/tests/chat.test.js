import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSystemPrompt, buildUserPrompt } from '../src/services/chat.js';

test('buildSystemPrompt includes grounding and JSON instructions', () => {
  const prompt = buildSystemPrompt({ language: 'en', transcriptLanguage: 'en' });
  assert.ok(prompt.includes('Return ONLY valid JSON'));
  assert.ok(prompt.includes('Answer only using the provided transcript chunks'));
});

test('buildUserPrompt lists chunks and question', () => {
  const prompt = buildUserPrompt({
    question: 'What was discussed?',
    title: 'Demo',
    topicContext: 'Note taking',
    speakerMetadata: { speakers: [{ name: 'A', role: 'PM' }] },
    chatHistory: [{ role: 'user', content: 'Hi' }],
    chunks: [{ id: 'chunk-1', start_time_seconds: 0, end_time_seconds: 10, text: 'Intro.' }]
  });
  assert.ok(prompt.includes('Transcript chunks'));
  assert.ok(prompt.includes('chunk-1'));
  assert.ok(prompt.includes('Question'));
});
