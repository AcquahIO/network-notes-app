import { query, getClient } from '../db.js';
import { chunkTranscriptSegments, buildQueryText } from './chunking.js';
import { getEmbedding, getEmbeddings } from './embeddings.js';
import { rankChunks } from './retrieval.js';

const normalizeRows = (rows) =>
  rows.map((row) => ({
    id: row.id,
    session_id: row.session_id,
    text: row.text,
    start_time_seconds: row.start_time_seconds,
    end_time_seconds: row.end_time_seconds,
    speaker: row.speaker,
    embedding: row.embedding,
    embedding_model: row.embedding_model,
    created_at: row.created_at
  }));

export const indexSessionTranscript = async (sessionId) => {
  const transcriptResult = await query(
    'SELECT start_time_seconds, end_time_seconds, text FROM transcript_segments WHERE session_id = $1 ORDER BY start_time_seconds ASC',
    [sessionId]
  );
  const segments = transcriptResult.rows;
  if (!segments.length) return { chunksIndexed: 0 };

  const chunks = chunkTranscriptSegments(segments);
  const { embeddings, model } = await getEmbeddings(chunks.map((chunk) => chunk.text));

  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query('DELETE FROM transcript_chunks WHERE session_id = $1', [sessionId]);

    for (let i = 0; i < chunks.length; i += 1) {
      const chunk = chunks[i];
      const embedding = embeddings[i] ?? null;
      await client.query(
        `INSERT INTO transcript_chunks (session_id, text, start_time_seconds, end_time_seconds, speaker, embedding, embedding_model)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          sessionId,
          chunk.text,
          chunk.start_time_seconds,
          chunk.end_time_seconds,
          chunk.speaker,
          embedding ? JSON.stringify(embedding) : null,
          model
        ]
      );
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  return { chunksIndexed: chunks.length, embeddingModel: model };
};

export const retrieveRelevantChunks = async ({ sessionId, question, chatHistory = [], limit = 8 }) => {
  const chunkResult = await query('SELECT * FROM transcript_chunks WHERE session_id = $1', [sessionId]);
  const chunks = normalizeRows(chunkResult.rows);
  if (!chunks.length) {
    return { chunks: [], topScore: 0 };
  }

  const queryText = buildQueryText({ question, chatHistory });
  const { embedding: queryEmbedding } = await getEmbedding(queryText);

  const ranked = rankChunks({ chunks, queryEmbedding, limit });
  const topScore = ranked[0]?.score ?? 0;
  return { chunks: ranked, topScore };
};
