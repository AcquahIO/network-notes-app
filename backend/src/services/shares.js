import crypto from 'crypto';
import { query, getClient } from '../db.js';
import { indexSessionTranscript } from './rag.js';

const DEFAULT_SCHEME = 'conferencenoteai://share';

const buildShareLink = (token) => {
  const base = process.env.APP_DEEP_LINK_BASE || DEFAULT_SCHEME;
  if (base.includes('?')) return `${base}&token=${token}`;
  return `${base}?token=${token}`;
};

export const createShare = async ({ sessionId, ownerUserId, scope = 'summary_transcript', expiresAt = null }) => {
  const token = crypto.randomBytes(24).toString('hex');
  const result = await query(
    `INSERT INTO shares (session_id, share_token, scope, owner_user_id, expires_at)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, share_token, scope, created_at, expires_at`,
    [sessionId, token, scope, ownerUserId, expiresAt]
  );

  return {
    share: result.rows[0],
    link: buildShareLink(token)
  };
};

export const getSharePayload = async ({ token }) => {
  const shareResult = await query(
    `SELECT * FROM shares
     WHERE share_token = $1 AND revoked = false
     AND (expires_at IS NULL OR expires_at > NOW())`,
    [token]
  );
  const share = shareResult.rows[0];
  if (!share) return null;

  const sessionResult = await query('SELECT * FROM sessions WHERE id = $1', [share.session_id]);
  const session = sessionResult.rows[0];
  if (!session) return null;

  const [summaryResult, transcriptResult, resourcesResult, chatLinksResult] = await Promise.all([
    query('SELECT * FROM summaries WHERE session_id = $1', [share.session_id]),
    query('SELECT * FROM transcript_segments WHERE session_id = $1 ORDER BY start_time_seconds ASC', [share.session_id]),
    query('SELECT * FROM resources WHERE session_id = $1 ORDER BY created_at DESC', [share.session_id]),
    query(
      'SELECT external_links_json FROM chat_messages WHERE session_id = $1 AND external_links_json IS NOT NULL',
      [share.session_id]
    )
  ]);

  const summary = summaryResult.rows[0] || null;
  const transcript = transcriptResult.rows;
  const resources = resourcesResult.rows;

  const externalLinks = chatLinksResult.rows
    .flatMap((row) => {
      if (!row.external_links_json) return [];
      if (typeof row.external_links_json === 'string') {
        try {
          return JSON.parse(row.external_links_json);
        } catch {
          return [];
        }
      }
      return row.external_links_json;
    })
    .filter((link) => link && link.url);

  const includeTranscript = share.scope !== 'summary_only';

  return {
    share,
    session,
    summary,
    transcript: includeTranscript ? transcript : [],
    resources,
    external_links: externalLinks
  };
};

export const importSharedSession = async ({ token, userId }) => {
  const payload = await getSharePayload({ token });
  if (!payload) return null;

  const { session, summary, transcript, resources, share, external_links } = payload;
  if (!summary) throw new Error('Shared session is missing summary data');

  const client = await getClient();
  let newSessionId;
  try {
    await client.query('BEGIN');
    const sessionInsert = await client.query(
      `INSERT INTO sessions (user_id, title, event_name, status, started_at, ended_at, duration_seconds, transcript_language, summary_language, speaker_metadata_json, topic_context, shared_from_session_id)
       VALUES ($1, $2, $3, 'ready', NOW(), NOW(), $4, $5, $6, $7, $8, $9)
       RETURNING id`,
      [
        userId,
        session.title,
        session.event_name,
        session.duration_seconds,
        session.transcript_language,
        session.summary_language,
        session.speaker_metadata_json,
        session.topic_context,
        session.id
      ]
    );
    newSessionId = sessionInsert.rows[0].id;

    if (transcript.length) {
      for (const seg of transcript) {
        await client.query(
          `INSERT INTO transcript_segments (session_id, start_time_seconds, end_time_seconds, text)
           VALUES ($1, $2, $3, $4)`,
          [newSessionId, seg.start_time_seconds, seg.end_time_seconds, seg.text]
        );
      }
    }

    await client.query(
      `INSERT INTO summaries (session_id, short_summary, detailed_summary, key_points_json, action_items_json, highlights_json, language)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (session_id) DO NOTHING`,
      [
        newSessionId,
        summary.short_summary,
        summary.detailed_summary,
        summary.key_points_json,
        summary.action_items_json,
        summary.highlights_json,
        summary.language
      ]
    );

    for (const resource of resources) {
      await client.query(
        `INSERT INTO resources (session_id, title, url, source_name, description)
         VALUES ($1, $2, $3, $4, $5)`,
        [newSessionId, resource.title, resource.url, resource.source_name, resource.description]
      );
    }

    if (Array.isArray(external_links)) {
      for (const link of external_links) {
        await client.query(
          `INSERT INTO resources (session_id, title, url, source_name, description)
           VALUES ($1, $2, $3, $4, $5)`,
          [newSessionId, link.title || 'Further reading', link.url, 'Further reading', link.note || null]
        );
      }
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  if (transcript.length) {
    indexSessionTranscript(newSessionId).catch((err) => {
      console.error('Failed to index imported session transcript', err);
    });
  }

  return { newSessionId, share };
};
