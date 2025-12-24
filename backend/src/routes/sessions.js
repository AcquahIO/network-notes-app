import express from 'express';
import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { authenticate } from '../middleware/auth.js';
import { query, getClient } from '../db.js';
import {
  generateSummaryFromTranscript,
  generateResourcesFromTranscript,
  generateTranscriptSegments
} from '../services/aiMock.js';
import { alignPhotosToSegments } from '../services/alignment.js';
import { generateStudyOutputsFromTranscript, openaiEnabled, transcribeAudioFile } from '../services/openai.js';
import { generateChatResponse } from '../services/chat.js';
import { indexSessionTranscript, retrieveRelevantChunks } from '../services/rag.js';
import { searchExternalReading } from '../services/search.js';
import { createShare } from '../services/shares.js';
import { sendEmail } from '../services/email.js';

const router = express.Router();

router.use(authenticate);

router.get('/', async (req, res) => {
  try {
    const result = await query(
      'SELECT id, title, status, started_at, ended_at, duration_seconds FROM sessions WHERE user_id = $1 ORDER BY started_at DESC',
      [req.user.id]
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to load sessions' });
  }
});

router.post('/', async (req, res) => {
  const { title, eventName } = req.body;
  try {
    const result = await query(
      `INSERT INTO sessions (user_id, title, event_name, status, started_at) 
       VALUES ($1, $2, $3, 'recording', NOW()) RETURNING id, title, status, started_at`,
      [req.user.id, title || 'Untitled Session', eventName || null]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to start session' });
  }
});

router.get('/:sessionId', async (req, res) => {
  const { sessionId } = req.params;
  try {
    const sessionResult = await query(
      'SELECT * FROM sessions WHERE id = $1 AND user_id = $2',
      [sessionId, req.user.id]
    );
    if (!sessionResult.rows.length) return res.status(404).json({ message: 'Session not found' });
    const session = sessionResult.rows[0];

    const [audio, photos, transcript, summary, resources, chatMessages] = await Promise.all([
      query('SELECT * FROM audio_recordings WHERE session_id = $1 ORDER BY created_at DESC LIMIT 1', [sessionId]),
      query('SELECT * FROM photos WHERE session_id = $1 ORDER BY taken_at_offset_seconds ASC', [sessionId]),
      query('SELECT * FROM transcript_segments WHERE session_id = $1 ORDER BY start_time_seconds ASC', [sessionId]),
      query('SELECT * FROM summaries WHERE session_id = $1', [sessionId]),
      query('SELECT * FROM resources WHERE session_id = $1 ORDER BY created_at DESC', [sessionId]),
      query('SELECT * FROM chat_messages WHERE session_id = $1 ORDER BY created_at ASC', [sessionId])
    ]);

    const alignedPhotos = alignPhotosToSegments(photos.rows, transcript.rows);

    res.json({
      session,
      audio: audio.rows[0] || null,
      photos: alignedPhotos,
      transcript: transcript.rows,
      summary: summary.rows[0] || null,
      resources: resources.rows,
      chat_messages: chatMessages.rows
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to fetch session' });
  }
});

router.post('/:sessionId/audio', async (req, res) => {
  const { sessionId } = req.params;
  const { fileUrl, durationSeconds, audioBase64, fileName, mimeType } = req.body;
  if (!fileUrl && !audioBase64) return res.status(400).json({ message: 'fileUrl or audioBase64 required' });

  try {
    const sessionCheck = await query('SELECT * FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, req.user.id]);
    if (!sessionCheck.rows.length) return res.status(404).json({ message: 'Session not found' });

    const storedFileUrl = audioBase64
      ? await saveUploadedAudio({ sessionId, audioBase64, fileName, mimeType })
      : fileUrl;

    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO audio_recordings (session_id, file_url, duration_seconds) VALUES ($1, $2, $3)`
        , [sessionId, storedFileUrl, durationSeconds || null]
      );
      await client.query(
        'UPDATE sessions SET status = $1, ended_at = NOW(), duration_seconds = COALESCE($2, duration_seconds) WHERE id = $3',
        ['processing', durationSeconds || null, sessionId]
      );
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    kickoffProcessing(sessionId).catch((err) => {
      console.error('Processing failed', err);
    });

    res.status(202).json({ message: 'Audio accepted, processing started' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to attach audio' });
  }
});

router.post('/:sessionId/photos', async (req, res) => {
  const { sessionId } = req.params;
  const { fileUrl, takenAtSeconds, ocrText } = req.body;
  if (!fileUrl) return res.status(400).json({ message: 'fileUrl required' });

  try {
    const sessionCheck = await query('SELECT id FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, req.user.id]);
    if (!sessionCheck.rows.length) return res.status(404).json({ message: 'Session not found' });

    const result = await query(
      `INSERT INTO photos (session_id, file_url, taken_at_offset_seconds, ocr_text) 
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [sessionId, fileUrl, takenAtSeconds || 0, ocrText || null]
    );

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to save photo' });
  }
});

router.post('/:sessionId/reindex', async (req, res) => {
  const { sessionId } = req.params;
  try {
    const sessionCheck = await query('SELECT id FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, req.user.id]);
    if (!sessionCheck.rows.length) return res.status(404).json({ message: 'Session not found' });
    const result = await indexSessionTranscript(sessionId);
    res.json({ message: 'Reindexed', chunksIndexed: result.chunksIndexed });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to reindex transcript' });
  }
});

router.post('/:sessionId/resummarize', async (req, res) => {
  const { sessionId } = req.params;
  const { speaker_metadata, topic_context, language } = req.body;
  try {
    const sessionResult = await query('SELECT * FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, req.user.id]);
    if (!sessionResult.rows.length) return res.status(404).json({ message: 'Session not found' });
    const session = sessionResult.rows[0];

    const transcriptResult = await query(
      'SELECT text FROM transcript_segments WHERE session_id = $1 ORDER BY start_time_seconds ASC',
      [sessionId]
    );
    if (!transcriptResult.rows.length) return res.status(400).json({ message: 'Transcript not ready yet' });

    const transcriptText = transcriptResult.rows.map((row) => row.text).join(' ');
    let summary;
    if (openaiEnabled()) {
      const outputs = await generateStudyOutputsFromTranscript({
        transcriptText,
        title: session.title,
        speakerMetadata: speaker_metadata ?? null,
        topicContext: topic_context ?? null,
        language: language ?? null
      });
      summary = outputs.summary;
    } else {
      summary = await generateSummaryFromTranscript({
        transcriptText,
        speakerMetadata: speaker_metadata ?? null,
        topicContext: topic_context ?? null,
        language: language ?? 'en'
      });
    }

    const summaryLanguage = summary.language ?? language ?? null;
    await query(
      `UPDATE sessions
       SET speaker_metadata_json = $1, topic_context = $2, summary_language = COALESCE($3, summary_language)
       WHERE id = $4`,
      [speaker_metadata ? JSON.stringify(speaker_metadata) : null, topic_context || null, summaryLanguage, sessionId]
    );

    await query(
      `INSERT INTO summaries (session_id, short_summary, detailed_summary, key_points_json, action_items_json, highlights_json, language)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (session_id) DO UPDATE
       SET short_summary = $2, detailed_summary = $3, key_points_json = $4, action_items_json = $5, highlights_json = $6, language = $7`,
      [
        sessionId,
        summary.short_summary,
        summary.detailed_summary,
        JSON.stringify(summary.key_points),
        JSON.stringify(summary.action_items),
        JSON.stringify(summary.highlights ?? []),
        summary.language ?? null
      ]
    );

    res.json({ summary });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to regenerate summary' });
  }
});

router.post('/:sessionId/chat', async (req, res) => {
  const { sessionId } = req.params;
  const { message, language, include_external_reading } = req.body;
  if (!message) return res.status(400).json({ message: 'message required' });

  try {
    const sessionResult = await query('SELECT * FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, req.user.id]);
    if (!sessionResult.rows.length) return res.status(404).json({ message: 'Session not found' });
    const session = sessionResult.rows[0];

    const chatHistoryResult = await query(
      'SELECT role, content FROM chat_messages WHERE session_id = $1 ORDER BY created_at DESC LIMIT 6',
      [sessionId]
    );
    const chatHistory = chatHistoryResult.rows.reverse();

    const chunksResult = await query('SELECT * FROM transcript_chunks WHERE session_id = $1', [sessionId]);
    if (!chunksResult.rows.length) {
      await indexSessionTranscript(sessionId);
    }

    const retrieval = await retrieveRelevantChunks({
      sessionId,
      question: message,
      chatHistory,
      limit: 8
    });

    const responseLanguage = language || session.summary_language || session.transcript_language || 'en';

    let speakerMetadata = session.speaker_metadata_json;
    if (typeof speakerMetadata === 'string') {
      try {
        speakerMetadata = JSON.parse(speakerMetadata);
      } catch {
        speakerMetadata = null;
      }
    }

    const lowConfidence = retrieval.topScore < 0.15 || retrieval.chunks.length === 0;
    const chatResponse = lowConfidence
      ? {
          answer:
            'That was not covered in this session. What part of the talk should I focus on, or do you want related background instead?',
          citations: [],
          language: responseLanguage
        }
      : await generateChatResponse({
          question: message,
          chunks: retrieval.chunks,
          chatHistory,
          language: responseLanguage,
          transcriptLanguage: session.transcript_language,
          title: session.title,
          topicContext: session.topic_context,
          speakerMetadata
        });

    const wantsExternal = Boolean(include_external_reading);
    let externalLinks = wantsExternal
      ? await searchExternalReading({
          query: `${message} ${session.title || ''}`.trim(),
          title: session.title,
          topicContext: session.topic_context
        })
      : [];
    if (lowConfidence && externalLinks.length) {
      externalLinks = externalLinks.map((link) => ({
        ...link,
        note: `Not discussed in the session; ${link.note || 'relevant background reading.'}`
      }));
    }

    await query(
      `INSERT INTO chat_messages (session_id, role, content, citations_json, external_links_json, language)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [sessionId, 'user', message, null, null, responseLanguage]
    );

    await query(
      `INSERT INTO chat_messages (session_id, role, content, citations_json, external_links_json, language)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        sessionId,
        'assistant',
        chatResponse.answer,
        JSON.stringify(chatResponse.citations ?? []),
        JSON.stringify(externalLinks ?? []),
        responseLanguage
      ]
    );

    res.json({
      assistant_message: chatResponse.answer,
      citations: chatResponse.citations ?? [],
      external_links: externalLinks
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to generate chat response' });
  }
});

router.post('/:sessionId/share', async (req, res) => {
  const { sessionId } = req.params;
  const { scope } = req.body;
  try {
    const sessionResult = await query('SELECT id FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, req.user.id]);
    if (!sessionResult.rows.length) return res.status(404).json({ message: 'Session not found' });
    const summaryResult = await query('SELECT session_id FROM summaries WHERE session_id = $1', [sessionId]);
    if (!summaryResult.rows.length) return res.status(400).json({ message: 'Summary not ready yet' });

    const shareResult = await createShare({
      sessionId,
      ownerUserId: req.user.id,
      scope: scope || 'summary_transcript'
    });

    res.json({
      share_token: shareResult.share.share_token,
      share_link: shareResult.link,
      scope: shareResult.share.scope
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to create share' });
  }
});

router.post('/:sessionId/share/email', async (req, res) => {
  const { sessionId } = req.params;
  const { emails, message, scope } = req.body;
  if (!Array.isArray(emails) || !emails.length) {
    return res.status(400).json({ message: 'emails must be a non-empty array' });
  }

  try {
    const sessionResult = await query('SELECT * FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, req.user.id]);
    if (!sessionResult.rows.length) return res.status(404).json({ message: 'Session not found' });
    const session = sessionResult.rows[0];

    const summaryResult = await query('SELECT * FROM summaries WHERE session_id = $1', [sessionId]);
    const summary = summaryResult.rows[0];
    if (!summary) return res.status(400).json({ message: 'Summary not ready yet' });

    const [resourcesResult, chatLinksResult] = await Promise.all([
      query('SELECT * FROM resources WHERE session_id = $1 ORDER BY created_at DESC', [sessionId]),
      query('SELECT external_links_json FROM chat_messages WHERE session_id = $1 AND external_links_json IS NOT NULL', [sessionId])
    ]);
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

    const shareResult = await createShare({
      sessionId,
      ownerUserId: req.user.id,
      scope: scope || 'summary_only'
    });

    let highlights = [];
    if (Array.isArray(summary.highlights_json)) {
      highlights = summary.highlights_json;
    } else if (summary.highlights_json) {
      try {
        highlights = JSON.parse(summary.highlights_json);
      } catch {
        highlights = [];
      }
    }
    const resourceLines = resources
      .map((resource) => `- ${resource.title}: ${resource.url}`)
      .join('\n');
    const externalLines = externalLinks
      .map((link) => `- ${link.title || link.url}: ${link.url}${link.note ? ` (${link.note})` : ''}`)
      .join('\n');

    const body = [
      `Session: ${session.title}`,
      '',
      'Summary:',
      summary.short_summary,
      '',
      '3 Key Highlights:',
      ...(highlights.length ? highlights.map((h) => `- ${h}`) : ['- Highlights not available.']),
      '',
      resourceLines ? `Resources:\n${resourceLines}` : 'Resources: None',
      externalLines ? `Further reading:\n${externalLines}` : null,
      '',
      `Share link: ${shareResult.link}`,
      message ? `\nNote from sender: ${message}` : null
    ]
      .filter(Boolean)
      .join('\n');

    await sendEmail({
      to: emails,
      subject: `Shared session summary: ${session.title}`,
      text: body
    });

    res.json({
      message: 'Email sent',
      share_link: shareResult.link
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to send share email' });
  }
});

const kickoffProcessing = async (sessionId) => {
  try {
    const audioResult = await query(
      'SELECT * FROM audio_recordings WHERE session_id = $1 ORDER BY created_at DESC LIMIT 1',
      [sessionId]
    );
    const audioRow = audioResult.rows[0];
    if (!audioRow) throw new Error(`No audio recording found for session ${sessionId}`);

    const sessionResult = await query('SELECT title FROM sessions WHERE id = $1', [sessionId]);
    const title = sessionResult.rows?.[0]?.title || null;

    const { transcriptSegments, summary, resources, transcriptLanguage } = await generateOutputsFromAudio({
      sessionId,
      audioFileUrl: audioRow.file_url,
      durationSeconds: audioRow.duration_seconds,
      title
    });

    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query('DELETE FROM transcript_segments WHERE session_id = $1', [sessionId]);

      for (const seg of transcriptSegments) {
        await client.query(
          `INSERT INTO transcript_segments (session_id, start_time_seconds, end_time_seconds, text)
           VALUES ($1, $2, $3, $4)`,
          [sessionId, seg.start_time_seconds, seg.end_time_seconds, seg.text]
        );
      }

      await client.query(
        `INSERT INTO summaries (session_id, short_summary, detailed_summary, key_points_json, action_items_json, highlights_json, language)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (session_id) DO UPDATE
         SET short_summary = $2, detailed_summary = $3, key_points_json = $4, action_items_json = $5, highlights_json = $6, language = $7`,
        [
          sessionId,
          summary.short_summary,
          summary.detailed_summary,
          JSON.stringify(summary.key_points),
          JSON.stringify(summary.action_items),
          JSON.stringify(summary.highlights ?? []),
          summary.language ?? null
        ]
      );

      await client.query('DELETE FROM resources WHERE session_id = $1', [sessionId]);
      for (const resource of resources) {
        await client.query(
          `INSERT INTO resources (session_id, title, url, source_name, description) VALUES ($1, $2, $3, $4, $5)`,
          [sessionId, resource.title, resource.url, resource.source_name, resource.description]
        );
      }

      await client.query(
        'UPDATE sessions SET status = $1, transcript_language = $2, summary_language = COALESCE($3, summary_language) WHERE id = $4',
        ['ready', transcriptLanguage, summary.language ?? null, sessionId]
      );
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      await query('UPDATE sessions SET status = $1 WHERE id = $2', ['failed', sessionId]);
      throw err;
    } finally {
      client.release();
    }
  } catch (err) {
    await query('UPDATE sessions SET status = $1 WHERE id = $2', ['failed', sessionId]);
    throw err;
  }

  indexSessionTranscript(sessionId).catch((err) => {
    console.error('Failed to index transcript chunks', err);
  });
};

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const UPLOADS_ROOT = path.join(__dirname, '../../uploads');
const AUDIO_UPLOADS_DIR = path.join(UPLOADS_ROOT, 'audio');

const stripDataUrlPrefix = (base64) => {
  if (typeof base64 !== 'string') return '';
  const trimmed = base64.trim();
  const commaIndex = trimmed.indexOf(',');
  if (trimmed.startsWith('data:') && commaIndex !== -1) return trimmed.slice(commaIndex + 1);
  return trimmed;
};

const safeAudioExtension = ({ fileName, mimeType }) => {
  const ext = typeof fileName === 'string' ? path.extname(fileName).toLowerCase() : '';
  if (ext === '.m4a' || ext === '.mp3' || ext === '.wav' || ext === '.mp4') return ext;
  if (mimeType === 'audio/wav') return '.wav';
  if (mimeType === 'audio/mpeg') return '.mp3';
  if (mimeType === 'audio/mp4' || mimeType === 'audio/x-m4a') return '.m4a';
  return '.m4a';
};

const saveUploadedAudio = async ({ sessionId, audioBase64, fileName, mimeType }) => {
  const base64 = stripDataUrlPrefix(audioBase64);
  if (!base64) throw new Error('audioBase64 was empty');

  const buffer = Buffer.from(base64, 'base64');
  if (!buffer.length) throw new Error('Decoded audio was empty');

  await fs.mkdir(AUDIO_UPLOADS_DIR, { recursive: true });
  const ext = safeAudioExtension({ fileName, mimeType });
  const key = crypto.randomUUID();
  const outName = `session_${sessionId}_${key}${ext}`;
  const outPath = path.join(AUDIO_UPLOADS_DIR, outName);
  await fs.writeFile(outPath, buffer);

  return `/uploads/audio/${outName}`;
};

const resolveAudioFilePath = (audioFileUrl) => {
  if (typeof audioFileUrl !== 'string') return null;
  if (audioFileUrl.startsWith('/uploads/')) {
    const rel = audioFileUrl.replace('/uploads/', '');
    return path.join(UPLOADS_ROOT, rel);
  }
  return null;
};

const generateOutputsFromAudio = async ({ sessionId, audioFileUrl, durationSeconds, title }) => {
  const filePath = resolveAudioFilePath(audioFileUrl);

  if (!openaiEnabled() || !filePath) {
    const transcriptSegments = await generateTranscriptSegments(sessionId);
    const transcriptText = transcriptSegments.map((s) => s.text).join(' ');
    const summary = await generateSummaryFromTranscript({ transcriptText, language: 'en' });
    const resources = await generateResourcesFromTranscript(transcriptText);
    return {
      transcriptText,
      transcriptSegments,
      summary,
      resources,
      transcriptLanguage: 'en'
    };
  }

  const transcription = await transcribeAudioFile({
    filePath,
    fileName: path.basename(filePath),
    mimeType: 'audio/mp4'
  });

  const transcriptText = transcription.text || transcription.segments.map((s) => s.text).join(' ');
  const transcriptSegments = (transcription.segments.length ? transcription.segments : [{ start: 0, end: Number(durationSeconds || 0), text: transcriptText }])
    .map((seg, idx) => ({
      session_id: sessionId,
      start_time_seconds: Math.max(0, Math.floor(seg.start || idx * 15)),
      end_time_seconds: Math.max(0, Math.ceil(seg.end || (idx * 15 + 15))),
      text: seg.text
    }))
    .filter((s) => s.text && s.end_time_seconds >= s.start_time_seconds);

  const outputs = await generateStudyOutputsFromTranscript({
    transcriptText,
    title,
    language: transcription.language || null
  });
  return {
    transcriptText,
    transcriptSegments,
    summary: outputs.summary,
    resources: outputs.resources,
    transcriptLanguage: transcription.language || null
  };
};

export default router;
