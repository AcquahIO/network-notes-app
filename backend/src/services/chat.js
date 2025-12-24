import { generateChatCompletion, openaiEnabled } from './openai.js';
import { generateChatResponseFromChunks } from './aiMock.js';

export const buildSystemPrompt = ({ language, transcriptLanguage }) => {
  return [
    'You are the session itself. Answer only using the provided transcript chunks.',
    'If the answer is not covered, say so explicitly and ask a follow-up question.',
    'Be concise by default; expand only if asked.',
    language ? `Respond in language: ${language}.` : null,
    transcriptLanguage && language && transcriptLanguage !== language
      ? `Citations can remain in the original transcript language (${transcriptLanguage}).`
      : null,
    'Return ONLY valid JSON with keys: answer (string), citations (array of {chunk_id, quote}).'
  ]
    .filter(Boolean)
    .join(' ');
};

export const buildUserPrompt = ({ question, title, topicContext, speakerMetadata, chunks, chatHistory }) => {
  const contextLines = [];
  if (title) contextLines.push(`Title: ${title}`);
  if (topicContext) contextLines.push(`Session context: ${topicContext}`);
  if (speakerMetadata) contextLines.push(`Speaker metadata: ${JSON.stringify(speakerMetadata)}`);

  const historyLines = chatHistory
    .map((msg) => `${msg.role === 'assistant' ? 'Assistant' : 'User'}: ${msg.content}`)
    .join('\n');

  const chunkLines = chunks
    .map(
      (chunk) =>
        `[${chunk.id}|${chunk.start_time_seconds ?? 'NA'}-${chunk.end_time_seconds ?? 'NA'}] ${chunk.text}`
    )
    .join('\n');

  return [
    contextLines.length ? contextLines.join('\n') : null,
    historyLines ? `Chat history:\n${historyLines}` : null,
    `Transcript chunks:\n${chunkLines}`,
    `Question:\n${question}`
  ]
    .filter(Boolean)
    .join('\n\n');
};

const normalizeCitations = ({ citations, chunks }) => {
  if (!Array.isArray(citations)) return [];
  const chunkMap = new Map(chunks.map((chunk) => [chunk.id, chunk]));
  return citations
    .map((citation) => {
      const chunk = chunkMap.get(citation?.chunk_id);
      if (!chunk) return null;
      return {
        chunk_id: chunk.id,
        start_time_seconds: chunk.start_time_seconds,
        end_time_seconds: chunk.end_time_seconds,
        text: String(citation?.quote ?? chunk.text).slice(0, 320)
      };
    })
    .filter(Boolean);
};

export const generateChatResponse = async ({
  question,
  chunks,
  chatHistory = [],
  language,
  transcriptLanguage,
  title,
  topicContext,
  speakerMetadata
}) => {
  if (!openaiEnabled()) {
    return generateChatResponseFromChunks({ question, chunks, language });
  }

  const messages = [
    {
      role: 'system',
      content: buildSystemPrompt({ language, transcriptLanguage })
    },
    {
      role: 'user',
      content: buildUserPrompt({ question, title, topicContext, speakerMetadata, chunks, chatHistory })
    }
  ];

  const parsed = await generateChatCompletion({ messages });
  const answer = String(parsed?.answer ?? '').trim();
  let citations = normalizeCitations({ citations: parsed?.citations, chunks });
  if (!citations.length && chunks.length) {
    const top = chunks[0];
    citations = [
      {
        chunk_id: top.id,
        start_time_seconds: top.start_time_seconds,
        end_time_seconds: top.end_time_seconds,
        text: String(top.text).slice(0, 320)
      }
    ];
  }

  return {
    answer: answer || 'This was not clearly covered in the session. What specific part should I focus on?',
    citations,
    language
  };
};
