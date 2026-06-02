#!/usr/bin/env bash
set -euo pipefail

MCPHUB_URL=${MCPHUB_URL:-http://127.0.0.1:47008}
MCPHUB_USERNAME=${MCPHUB_USERNAME:-admin}
MCPHUB_PASSWORD=${MCPHUB_PASSWORD:-admin123}
POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-shared-postgres}
PLUGIN_IDENTIFIER=${PLUGIN_IDENTIFIER:-mcphub-fs}
MCP_SERVER=${MCP_SERVER:-filesystem}
DEFAULT_AGENT_MODEL=${DEFAULT_AGENT_MODEL:-gpt-4.1-mini}
DEFAULT_AGENT_PROVIDER=${DEFAULT_AGENT_PROVIDER:-openai}

tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

token=$(
  curl -fsS -X POST "${MCPHUB_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${MCPHUB_USERNAME}\",\"password\":\"${MCPHUB_PASSWORD}\"}" |
    jq -er '.token'
)
curl -fsS -H "x-auth-token: ${token}" "${MCPHUB_URL}/api/servers" > "${tmp_dir}/servers.json"

user_id=$(
  docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat -tAc \
    "SELECT id FROM users ORDER BY created_at DESC LIMIT 1;"
)
agent_id=$(
  docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat -tAc \
    "SELECT id FROM agents WHERE user_id = '${user_id}' ORDER BY updated_at DESC LIMIT 1;"
)

python3 - "${tmp_dir}/servers.json" "${tmp_dir}/register.sql" "${user_id}" "${agent_id}" "${MCP_SERVER}" "${PLUGIN_IDENTIFIER}" "${DEFAULT_AGENT_MODEL}" "${DEFAULT_AGENT_PROVIDER}" <<'PY'
import json
import sys

servers_path, sql_path, user_id, agent_id, mcp_server, plugin_id, model, provider = sys.argv[1:]
servers = json.load(open(servers_path, encoding="utf-8"))["data"]
server = next(item for item in servers if item["name"] == mcp_server)
if server["status"] != "connected":
    raise SystemExit(f"{mcp_server} MCP is not connected")

api = [
    {
        "name": tool["name"],
        "description": tool.get("description", ""),
        "parameters": tool.get("inputSchema", {"type": "object", "properties": {}}),
    }
    for tool in server["tools"]
]
manifest = {
    "identifier": plugin_id,
    "type": "mcp",
    "meta": {
        "title": plugin_id,
        "avatar": "MCP_AVATAR",
        "description": f"{plugin_id} MCP server has {len(api)} tools",
    },
    "api": api,
}
custom_params = {
    "mcp": {
        "url": f"http://mcphub:3000/mcp/{mcp_server}",
        "auth": {"type": "none"},
        "type": "http",
    }
}

def quote(value: str) -> str:
    return value.replace("'", "''")

manifest_json = quote(json.dumps(manifest))
custom_json = quote(json.dumps(custom_params))
plugin_json = quote(json.dumps([plugin_id]))
default_config_json = quote(json.dumps({"model": model, "provider": provider, "plugins": [plugin_id]}))
model_registry_sql = ""
if model == "gpt-4.1-mini" and provider == "openai":
    model_registry_sql = f"""
INSERT INTO ai_providers (id, user_id, enabled, source, settings, config)
VALUES ('openai', '{quote(user_id)}', TRUE, 'builtin', '{{}}'::jsonb, '{{}}'::jsonb)
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
  '{quote(user_id)}',
  '{{"functionCall":true,"vision":true,"reasoning":false,"imageOutput":false,"search":false,"video":false}}'::jsonb,
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
"""

sql = f"""
{model_registry_sql}
INSERT INTO user_installed_plugins (user_id, identifier, type, manifest, custom_params)
VALUES ('{quote(user_id)}', '{quote(plugin_id)}', 'customPlugin',
        '{manifest_json}'::jsonb, '{custom_json}'::jsonb)
ON CONFLICT (user_id, identifier) DO UPDATE
SET type = EXCLUDED.type,
    manifest = EXCLUDED.manifest,
    custom_params = EXCLUDED.custom_params,
    updated_at = NOW();

UPDATE agents
SET plugins = CASE
      WHEN COALESCE(plugins, '[]'::jsonb) ? '{quote(plugin_id)}' THEN plugins
      ELSE COALESCE(plugins, '[]'::jsonb) || '{plugin_json}'::jsonb
    END,
    updated_at = NOW()
WHERE id = '{quote(agent_id)}';

INSERT INTO user_settings (id, default_agent)
VALUES ('{quote(user_id)}', jsonb_build_object('config', '{default_config_json}'::jsonb))
ON CONFLICT (id) DO UPDATE
SET default_agent = COALESCE(user_settings.default_agent, '{{}}'::jsonb) ||
    jsonb_build_object(
      'config',
      COALESCE(user_settings.default_agent->'config', '{{}}'::jsonb) ||
      jsonb_build_object(
        'model', '{quote(model)}',
        'provider', '{quote(provider)}',
        'plugins',
        CASE
          WHEN COALESCE(user_settings.default_agent->'config'->'plugins', '[]'::jsonb) ? '{quote(plugin_id)}'
            THEN COALESCE(user_settings.default_agent->'config'->'plugins', '[]'::jsonb)
          ELSE COALESCE(user_settings.default_agent->'config'->'plugins', '[]'::jsonb) || '{plugin_json}'::jsonb
        END
      )
    );
"""
open(sql_path, "w", encoding="utf-8").write(sql)
PY

docker exec -i "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat < "${tmp_dir}/register.sql"
docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat -c \
  "SELECT id, model, provider, plugins FROM agents WHERE id = '${agent_id}';"
docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d lobechat -c \
  "SELECT id, default_agent FROM user_settings WHERE id = '${user_id}';"
