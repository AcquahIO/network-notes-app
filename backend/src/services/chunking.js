const estimateTokens = (text) => {
  if (typeof text !== 'string' || text.length === 0) return 0;
  const words = text.trim().split(/\s+/).length;
  return Math.ceil(words * 1.3);
};

export const chunkTranscriptSegments = (segments, { maxTokens = 700, minTokens = 200 } = {}) => {
  const chunks = [];
  let current = [];
  let currentTokens = 0;
  let start = null;
  let end = null;

  const flush = () => {
    if (!current.length) return;
    chunks.push({
      text: current.join(' ').trim(),
      start_time_seconds: start ?? 0,
      end_time_seconds: end ?? start ?? 0,
      speaker: null
    });
    current = [];
    currentTokens = 0;
    start = null;
    end = null;
  };

  for (const segment of segments) {
    const text = String(segment?.text ?? '').trim();
    if (!text) continue;

    const segTokens = estimateTokens(text);
    if (start === null) start = Number(segment.start_time_seconds ?? 0);
    end = Number(segment.end_time_seconds ?? segment.start_time_seconds ?? 0);

    if (currentTokens + segTokens > maxTokens && currentTokens >= minTokens) {
      flush();
      start = Number(segment.start_time_seconds ?? 0);
      end = Number(segment.end_time_seconds ?? segment.start_time_seconds ?? 0);
    }

    current.push(text);
    currentTokens += segTokens;
  }

  flush();
  return chunks.filter((chunk) => chunk.text.length > 0);
};

export const buildQueryText = ({ question, chatHistory = [] }) => {
  const historyText = chatHistory
    .map((msg) => `${msg.role === 'assistant' ? 'Assistant' : 'User'}: ${msg.content}`)
    .join('\n');
  return [historyText, question].filter(Boolean).join('\n');
};
