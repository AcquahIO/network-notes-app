const getSearchConfig = () => ({
  apiKey: process.env.GOOGLE_SEARCH_API_KEY,
  cx: process.env.GOOGLE_SEARCH_CX,
  maxResults: Number(process.env.GOOGLE_SEARCH_MAX_RESULTS || 5)
});

export const searchEnabled = () => {
  const { apiKey, cx } = getSearchConfig();
  return Boolean(apiKey && cx);
};

const buildNote = ({ title, topicContext }) => {
  if (topicContext) {
    return `Background reading related to the session topic "${topicContext}".`;
  }
  if (title) {
    return `Background reading related to the session "${title}".`;
  }
  return 'Background reading related to the session discussion.';
};

export const searchExternalReading = async ({ query, title, topicContext }) => {
  if (!searchEnabled()) return [];

  const { apiKey, cx, maxResults } = getSearchConfig();
  const url = new URL('https://www.googleapis.com/customsearch/v1');
  url.searchParams.set('key', apiKey);
  url.searchParams.set('cx', cx);
  url.searchParams.set('q', query);

  try {
    const res = await fetch(url, { headers: { 'User-Agent': 'ConferenceNoteAI/1.0' } });
    if (!res.ok) return [];
    const json = await res.json();
    const items = Array.isArray(json.items) ? json.items : [];
    return items.slice(0, maxResults).map((item) => ({
      title: String(item.title ?? '').trim(),
      url: String(item.link ?? '').trim(),
      note: buildNote({ title, topicContext })
    })).filter((item) => item.title && item.url);
  } catch (err) {
    console.error('Search failed', err);
    return [];
  }
};
