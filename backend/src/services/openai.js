import fs from 'fs/promises';

const getConfig = () => ({
  baseURL: process.env.OPENAI_BASE_URL || 'https://api.openai.com',
  apiKey: process.env.OPENAI_API_KEY,
  transcribeModel: process.env.OPENAI_TRANSCRIBE_MODEL || 'gpt-4o-transcribe',
  summaryModel: process.env.OPENAI_SUMMARY_MODEL || 'gpt-4o',
  chatModel: process.env.OPENAI_CHAT_MODEL || process.env.OPENAI_SUMMARY_MODEL || 'gpt-4o',
  embedModel: process.env.OPENAI_EMBED_MODEL || 'text-embedding-3-small',
  timeoutMs: Number(process.env.OPENAI_TIMEOUT_MS || 120_000)
});

const requireApiKey = () => {
  if (!process.env.OPENAI_API_KEY) {
    throw new Error('OPENAI_API_KEY is not set');
  }
};

const openaiFetchJson = async (path, { method = 'GET', headers = {}, body, timeoutMs } = {}) => {
  requireApiKey();
  const { apiKey, baseURL, timeoutMs: defaultTimeoutMs } = getConfig();

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs ?? defaultTimeoutMs);
  try {
    const res = await fetch(`${baseURL}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        ...headers
      },
      body,
      signal: controller.signal
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`OpenAI request failed (${res.status}) ${text || res.statusText}`);
    }

    return await res.json();
  } finally {
    clearTimeout(timeout);
  }
};

export const openaiEnabled = () => Boolean(process.env.OPENAI_API_KEY);

const getTranscribeResponseFormat = (model) => {
  const normalized = String(model || '').toLowerCase();
  if (normalized.includes('whisper')) return 'verbose_json';
  return 'json';
};

export const transcribeAudioFile = async ({ filePath, fileName = 'audio.m4a', mimeType = 'audio/mp4' }) => {
  const { transcribeModel, timeoutMs } = getConfig();
  const data = await fs.readFile(filePath);
  const responseFormat = getTranscribeResponseFormat(transcribeModel);

  const form = new FormData();
  form.append('model', transcribeModel);
  form.append('file', new Blob([data], { type: mimeType }), fileName);
  form.append('response_format', responseFormat);
  form.append('temperature', '0');
  if (responseFormat === 'verbose_json') {
    form.append('timestamp_granularities[]', 'segment');
  }

  const json = await openaiFetchJson('/v1/audio/transcriptions', {
    method: 'POST',
    body: form,
    timeoutMs
  });

  const text = typeof json.text === 'string' ? json.text : '';
  const language = typeof json.language === 'string' ? json.language : null;
  const segments = Array.isArray(json.segments) ? json.segments : [];

  return {
    text,
    language,
    segments: segments
      .map((seg) => ({
        start: Number(seg.start ?? 0),
        end: Number(seg.end ?? 0),
        text: String(seg.text ?? '').trim()
      }))
      .filter((seg) => seg.text.length > 0)
  };
};

const coerceStringArray = (value) => {
  if (Array.isArray(value)) return value.map((v) => String(v)).filter((v) => v.length > 0);
  return [];
};

const coerceResources = (value) => {
  if (!Array.isArray(value)) return [];
  return value
    .map((r) => ({
      title: String(r?.title ?? '').trim(),
      url: String(r?.url ?? '').trim(),
      source_name: String(r?.source_name ?? '').trim(),
      description: String(r?.description ?? '').trim()
    }))
    .filter((r) => r.title && r.url);
};

const coerceHighlights = (value) => {
  const highlights = coerceStringArray(value);
  if (highlights.length === 3) return highlights;
  if (highlights.length > 3) return highlights.slice(0, 3);
  while (highlights.length < 3) highlights.push('Highlight not available.');
  return highlights;
};

const safeJsonParse = (content) => {
  if (typeof content !== 'string' || content.trim().length === 0) return null;
  try {
    return JSON.parse(content);
  } catch {
    return null;
  }
};

const splitTranscript = (text, maxChars) => {
  if (text.length <= maxChars) return [text];
  const words = text.split(/\s+/).filter(Boolean);
  const chunks = [];
  let current = [];
  let length = 0;
  for (const word of words) {
    current.push(word);
    length += word.length + 1;
    if (length >= maxChars) {
      chunks.push(current.join(' '));
      current = [];
      length = 0;
    }
  }
  if (current.length) chunks.push(current.join(' '));
  return chunks;
};

const buildSummarySystemPrompt = ({ language, speakerMetadata, topicContext }) => {
  const contextLines = [];
  if (speakerMetadata) {
    contextLines.push(`Speaker metadata: ${JSON.stringify(speakerMetadata)}`);
  }
  if (topicContext) {
    contextLines.push(`Session context: ${topicContext}`);
  }
  if (language) {
    contextLines.push(`Respond in language: ${language}.`);
  }
  return (
    'You summarize talk transcripts. Return ONLY valid JSON with keys: ' +
    'short_summary (string), detailed_summary (string), key_points (string[]), action_items (string[]), ' +
    'highlights (string[3]), language (string), resources (array of {title,url,source_name,description}). ' +
    'Highlights must be exactly 3 items. Keep the summary grounded in the transcript. ' +
    (contextLines.length ? `Context:\n${contextLines.join('\n')}` : '')
  );
};

const summarizeTranscriptChunk = async ({ transcriptText, title, idx, total, timeoutMs }) => {
  const { summaryModel } = getConfig();
  const payload = {
    model: summaryModel,
    temperature: 0.2,
    response_format: { type: 'json_object' },
    messages: [
      {
        role: 'system',
        content:
          'Summarize this transcript chunk. Return ONLY valid JSON with keys: ' +
          'chunk_summary (string), key_points (string[]). Keep it grounded in the text.'
      },
      {
        role: 'user',
        content: [
          title ? `Title: ${title}` : null,
          `Chunk ${idx + 1} of ${total}:`,
          transcriptText
        ]
          .filter(Boolean)
          .join('\n')
      }
    ]
  };

  const json = await openaiFetchJson('/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    timeoutMs
  });

  const parsed = safeJsonParse(json?.choices?.[0]?.message?.content);
  const chunkSummary = String(parsed?.chunk_summary ?? '').trim();
  const keyPoints = coerceStringArray(parsed?.key_points);

  return {
    chunkSummary: chunkSummary || 'Chunk summary unavailable.',
    keyPoints
  };
};

export const generateStudyOutputsFromTranscript = async ({
  transcriptText,
  title,
  speakerMetadata = null,
  topicContext = null,
  language = null
}) => {
  const { summaryModel, timeoutMs } = getConfig();
  const maxChunkChars = 12000;
  const chunks = splitTranscript(transcriptText, maxChunkChars);

  let condensedTranscript = transcriptText;
  if (chunks.length > 1) {
    const chunkSummaries = [];
    for (const [idx, chunk] of chunks.entries()) {
      const chunkResult = await summarizeTranscriptChunk({
        transcriptText: chunk,
        title,
        idx,
        total: chunks.length,
        timeoutMs
      });
      chunkSummaries.push(
        `Chunk ${idx + 1}: ${chunkResult.chunkSummary}\nKey points: ${chunkResult.keyPoints.join('; ')}`
      );
    }
    condensedTranscript = chunkSummaries.join('\n\n');
  }

  const payload = {
    model: summaryModel,
    temperature: 0.2,
    response_format: { type: 'json_object' },
    messages: [
      {
        role: 'system',
        content: buildSummarySystemPrompt({ language, speakerMetadata, topicContext })
      },
      {
        role: 'user',
        content: [
          title ? `Title: ${title}` : null,
          chunks.length > 1 ? 'Transcript summary (chunked):' : 'Transcript:',
          condensedTranscript
        ]
          .filter(Boolean)
          .join('\n')
      }
    ]
  };

  const json = await openaiFetchJson('/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    timeoutMs
  });

  const parsed = safeJsonParse(json?.choices?.[0]?.message?.content);
  if (!parsed) throw new Error('OpenAI summary response was not valid JSON');

  const short_summary = String(parsed.short_summary ?? '').trim();
  const detailed_summary = String(parsed.detailed_summary ?? '').trim();
  const key_points = coerceStringArray(parsed.key_points);
  const action_items = coerceStringArray(parsed.action_items);
  const highlights = coerceHighlights(parsed.highlights);
  const resources = coerceResources(parsed.resources);
  const summaryLanguage = String(parsed.language ?? language ?? '').trim() || null;

  if (!short_summary || !detailed_summary) {
    throw new Error('OpenAI summary response missing required fields');
  }

  return {
    summary: {
      short_summary,
      detailed_summary,
      key_points,
      action_items,
      highlights,
      language: summaryLanguage
    },
    resources
  };
};

export const generateEmbeddings = async (texts) => {
  const { embedModel, timeoutMs } = getConfig();
  if (!Array.isArray(texts) || !texts.length) return [];

  const payload = {
    model: embedModel,
    input: texts
  };

  const json = await openaiFetchJson('/v1/embeddings', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    timeoutMs
  });

  const data = Array.isArray(json?.data) ? json.data : [];
  return data.map((item) => item.embedding).filter(Boolean);
};

export const generateChatCompletion = async ({ messages, temperature = 0.2 }) => {
  const { chatModel, timeoutMs } = getConfig();
  const payload = {
    model: chatModel,
    temperature,
    response_format: { type: 'json_object' },
    messages
  };

  const json = await openaiFetchJson('/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    timeoutMs
  });

  return safeJsonParse(json?.choices?.[0]?.message?.content);
};
