const demoSummary = `Speaker outlined a practical path for AI-assisted note taking and study workflows, focusing on capturing audio and slide context with minimal friction.`;

export const generateSummaryFromTranscript = async ({
  transcriptText,
  speakerMetadata = null,
  topicContext = null,
  language = 'en'
} = {}) => {
  const metadataNote = speakerMetadata?.speakers?.length
    ? `Speakers include ${speakerMetadata.speakers.map((s) => `${s.name}${s.role ? ` (${s.role})` : ''}`).join(', ')}. `
    : '';
  const contextNote = topicContext ? `Session context: ${topicContext}. ` : '';
  return {
    short_summary: `${metadataNote}${contextNote}${demoSummary}`,
    detailed_summary: `${demoSummary} The talk emphasized aligning photos to transcript timestamps and delivering concise study-ready outputs.`,
    key_points: [
      'Capture audio and slides together to preserve context.',
      'Auto-transcribe and align images to transcript segments.',
      'Provide TL;DR, takeaways, and study resources quickly.'
    ],
    action_items: [
      'Test the recording workflow in noisy environments.',
      'Prototype AI alignment on a larger sample.',
      'Ship resource recommendations backed by search.'
    ],
    highlights: [
      'Audio + slide capture keeps context intact.',
      'Transcript alignment speeds review.',
      'Study summaries make sessions reusable.'
    ],
    language
  };
};

export const generateResourcesFromTranscript = async (transcriptText) => {
  // TODO: replace with LLM + web search
  return [
    {
      title: 'Designing delightful capture flows',
      url: 'https://example.com/designing-capture-flows',
      source_name: 'Product Patterns',
      description: 'Patterns for low-friction capture with progressive disclosure.'
    },
    {
      title: 'Building robust audio recorders on iOS',
      url: 'https://example.com/ios-audio-recording',
      source_name: 'iOS Audio Guide',
      description: 'Best practices for AVAudioSession, background modes, and interruptions.'
    }
  ];
};

export const generateTranscriptSegments = async (sessionId) => {
  // TODO: replace with real transcription service
  const base = [
    'Welcome to Conference Note AI, where we help you capture talks effortlessly.',
    'We align slide photos to the transcript so you can revisit moments quickly.',
    'Our study hub surfaces key takeaways and related resources.',
    'Future versions will ship real AI summaries and smart resource discovery.'
  ];
  return base.map((text, idx) => ({
    session_id: sessionId,
    start_time_seconds: idx * 45,
    end_time_seconds: idx * 45 + 40,
    text
  }));
};

export const generateChatResponseFromChunks = async ({ question, chunks, language = 'en' }) => {
  const fallback = 'That was not directly covered in this session. Can you clarify what part you want to focus on?';
  const topChunk = chunks?.[0];
  if (!topChunk) {
    return {
      answer: fallback,
      citations: [],
      language
    };
  }

  return {
    answer: `From what was discussed, the session highlights: ${topChunk.text.slice(0, 160)}...`,
    citations: [
      {
        chunk_id: topChunk.id,
        start_time_seconds: topChunk.start_time_seconds,
        end_time_seconds: topChunk.end_time_seconds,
        text: topChunk.text
      }
    ],
    language
  };
};
