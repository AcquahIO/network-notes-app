import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const testDb = process.env.TEST_DATABASE_URL;

if (!testDb) {
  test('integration tests (set TEST_DATABASE_URL to enable)', { skip: true }, () => {});
} else {
  process.env.DATABASE_URL = testDb;
  const { query } = await import('../src/db.js');
  const { createShare, importSharedSession, getSharePayload } = await import('../src/services/shares.js');

  test('share + import flow', async () => {
    const email = `test-${crypto.randomUUID()}@example.com`;
    const userResult = await query(
      'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id',
      [email, 'hash']
    );
    const userId = userResult.rows[0].id;

    const sessionResult = await query(
      `INSERT INTO sessions (user_id, title, status)
       VALUES ($1, $2, 'ready') RETURNING id`,
      [userId, 'Shared Session']
    );
    const sessionId = sessionResult.rows[0].id;

    await query(
      `INSERT INTO summaries (session_id, short_summary, detailed_summary, key_points_json, action_items_json, highlights_json, language)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [sessionId, 'Short', 'Detailed', JSON.stringify(['a']), JSON.stringify(['b']), JSON.stringify(['h1','h2','h3']), 'en']
    );
    await query(
      `INSERT INTO transcript_segments (session_id, start_time_seconds, end_time_seconds, text)
       VALUES ($1, $2, $3, $4)`,
      [sessionId, 0, 10, 'Transcript text']
    );

    const shareResult = await createShare({ sessionId, ownerUserId: userId, scope: 'summary_transcript' });
    assert.ok(shareResult.link.includes('token='));

    const payload = await getSharePayload({ token: shareResult.share.share_token });
    assert.equal(payload.session.id, sessionId);

    const imported = await importSharedSession({ token: shareResult.share.share_token, userId });
    assert.ok(imported.newSessionId);
  });
}
