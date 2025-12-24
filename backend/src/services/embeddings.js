import { generateEmbeddings, openaiEnabled } from './openai.js';

const EMBEDDING_DIM = 128;

const normalize = (vector) => {
  const norm = Math.sqrt(vector.reduce((sum, val) => sum + val * val, 0)) || 1;
  return vector.map((val) => val / norm);
};

const hashToken = (token) => {
  let hash = 0;
  for (let i = 0; i < token.length; i += 1) {
    hash = (hash * 31 + token.charCodeAt(i)) | 0;
  }
  return Math.abs(hash);
};

const mockEmbedding = (text) => {
  const vector = new Array(EMBEDDING_DIM).fill(0);
  const tokens = String(text ?? '')
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean);
  for (const token of tokens) {
    const index = hashToken(token) % EMBEDDING_DIM;
    vector[index] += 1;
  }
  return normalize(vector);
};

export const getEmbeddings = async (texts) => {
  if (!Array.isArray(texts) || texts.length === 0) {
    return { embeddings: [], model: openaiEnabled() ? 'openai' : 'mock-bow-128' };
  }

  if (!openaiEnabled()) {
    return { embeddings: texts.map(mockEmbedding), model: 'mock-bow-128' };
  }

  const embeddings = await generateEmbeddings(texts);
  if (!embeddings.length) {
    return { embeddings: texts.map(mockEmbedding), model: 'mock-bow-128' };
  }
  return { embeddings, model: process.env.OPENAI_EMBED_MODEL || 'text-embedding-3-small' };
};

export const getEmbedding = async (text) => {
  const result = await getEmbeddings([text]);
  return { embedding: result.embeddings[0] ?? mockEmbedding(text), model: result.model };
};
