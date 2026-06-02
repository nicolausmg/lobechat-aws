#!/usr/bin/env bash
set -euo pipefail

POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-shared-postgres}
AGENT_ID=${AGENT_ID:-agt_McpEvidence01}
SESSION_ID=${SESSION_ID:-ssn_McpEvidence01}

user_id=$(
  docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat -tAc \
    "SELECT id FROM users ORDER BY created_at DESC LIMIT 1;"
)

if [[ -z "${user_id}" ]]; then
  echo "No LobeChat user found. Log in through Casdoor first." >&2
  exit 1
fi

docker exec -i "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat <<SQL
INSERT INTO ai_providers (id, user_id, enabled, source, settings, config)
VALUES ('openai', '${user_id}', TRUE, 'builtin', '{}'::jsonb, '{}'::jsonb)
ON CONFLICT (id, user_id) DO UPDATE
SET enabled = TRUE,
    source = EXCLUDED.source,
    updated_at = NOW();

INSERT INTO ai_models (
  id, display_name, enabled, provider_id, type, user_id, abilities,
  context_window_tokens, source, released_at
)
VALUES (
  'gpt-4.1-mini',
  'GPT-4.1 mini',
  TRUE,
  'openai',
  'chat',
  '${user_id}',
  '{"functionCall":true,"vision":true,"reasoning":false,"imageOutput":false,"search":false,"video":false}'::jsonb,
  1047576,
  'builtin',
  '2025-04-14'
)
ON CONFLICT (id, provider_id, user_id) DO UPDATE
SET display_name = EXCLUDED.display_name,
    enabled = TRUE,
    abilities = EXCLUDED.abilities,
    context_window_tokens = EXCLUDED.context_window_tokens,
    source = EXCLUDED.source,
    released_at = EXCLUDED.released_at,
    updated_at = NOW();

INSERT INTO agents (
  id, slug, title, description, model, provider, plugins, user_id,
  opening_message, avatar, background_color, chat_config, params, system_role
)
VALUES (
  '${AGENT_ID}',
  'mcp-evidence-assistant',
  'MCP Evidence Assistant',
  'Runs a filesystem MCP tool call for deployment evidence.',
  'gpt-4.1-mini',
  'openai',
  '["mcphub-fs"]'::jsonb,
  '${user_id}',
  'Ask me to list the allowed filesystem directories. I will use the filesystem MCP tool.',
  '🧰',
  '#0f766e',
  '{"displayMode":"chat","enableAutoCreateTopic":true,"enableHistoryCount":false,"historyCount":8}'::jsonb,
  '{"temperature":0.1,"top_p":0.9}'::jsonb,
  'You are an MCP evidence assistant. When asked to list allowed filesystem directories, you MUST call filesystem-list_allowed_directories using the mcphub-fs plugin before answering. Never guess or simulate a tool result. Return the MCP result concisely.'
)
ON CONFLICT (id) DO UPDATE
SET model = EXCLUDED.model,
    provider = EXCLUDED.provider,
    plugins = EXCLUDED.plugins,
    opening_message = EXCLUDED.opening_message,
    chat_config = EXCLUDED.chat_config,
    params = EXCLUDED.params,
    system_role = EXCLUDED.system_role,
    updated_at = NOW();

INSERT INTO sessions (
  id, slug, title, description, type, user_id, avatar, background_color
)
VALUES (
  '${SESSION_ID}',
  'mcp-evidence-assistant',
  'MCP Evidence Assistant',
  'Runs a filesystem MCP tool call for deployment evidence.',
  'agent',
  '${user_id}',
  '🧰',
  '#0f766e'
)
ON CONFLICT (id) DO UPDATE
SET title = EXCLUDED.title,
    description = EXCLUDED.description,
    avatar = EXCLUDED.avatar,
    background_color = EXCLUDED.background_color,
    updated_at = NOW();

INSERT INTO agents_to_sessions (agent_id, session_id, user_id)
VALUES ('${AGENT_ID}', '${SESSION_ID}', '${user_id}')
ON CONFLICT (agent_id, session_id) DO NOTHING;
SQL

docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat -c \
  "SELECT a.id, a.title, a.model, a.provider, a.plugins, s.id AS session_id, s.slug
   FROM agents a
   JOIN agents_to_sessions ats ON ats.agent_id = a.id
   JOIN sessions s ON s.id = ats.session_id
   WHERE a.id = '${AGENT_ID}';"
