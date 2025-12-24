ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS transcript_language TEXT,
  ADD COLUMN IF NOT EXISTS summary_language TEXT,
  ADD COLUMN IF NOT EXISTS speaker_metadata_json JSONB,
  ADD COLUMN IF NOT EXISTS topic_context TEXT,
  ADD COLUMN IF NOT EXISTS shared_from_session_id UUID REFERENCES sessions(id);

ALTER TABLE summaries
  ADD COLUMN IF NOT EXISTS highlights_json JSONB,
  ADD COLUMN IF NOT EXISTS language TEXT;

CREATE TABLE IF NOT EXISTS transcript_chunks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  start_time_seconds INTEGER,
  end_time_seconds INTEGER,
  speaker TEXT,
  embedding JSONB,
  embedding_model TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  citations_json JSONB,
  external_links_json JSONB,
  language TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS shares (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
  share_token TEXT UNIQUE NOT NULL,
  scope TEXT NOT NULL,
  owner_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  permissions TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  revoked BOOLEAN NOT NULL DEFAULT FALSE
);
