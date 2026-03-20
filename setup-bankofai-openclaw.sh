#!/bin/bash

# BankOfAI Setup Script for OpenClaw
# Quickly configure BankOfAI models in OpenClaw

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
cat << "EOF"
   _    ___ _   _ _____ _____
  / \  |_ _| \ | |  ___|_   _|
 / _ \  | ||  \| | |_    | |
/ ___ \ | || |\  |  _|   | |
/_/   \_\___|_| \_|_|     |_|

OpenClaw Integration Setup
EOF
echo -e "${NC}"

CONFIG_FILE="$HOME/.openclaw/openclaw.json"
AINFT_CONFIG_DIR="$HOME/.ainft"
AINFT_CONFIG_FILE="$AINFT_CONFIG_DIR/config.json"
TMP_AINFT_MODEL_FILE="$(mktemp)"
trap 'rm -f "$TMP_AINFT_MODEL_FILE"' EXIT

require_python3() {
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python 3 is required but not found in PATH.${NC}"
        exit 1
    fi
}

check_node_version() {
    if ! command -v node &> /dev/null; then
        echo -e "${RED}Node.js is not installed or not in PATH.${NC}"
        exit 1
    fi

    local node_version major_version
    node_version="$(node -v 2>/dev/null || true)"
    major_version="$(echo "$node_version" | sed -E 's/^v([0-9]+).*/\1/')"
    if [ -z "$major_version" ] || [ "$major_version" -lt 22 ]; then
        echo -e "${RED}Node.js >= 22 is required. Current version: ${node_version:-unknown}${NC}"
        exit 1
    fi
}

confirm_overwrite() {
    local target="$1"
    local prompt="$2"
    local answer

    if [ ! -f "$target" ]; then
        return 0
    fi

    echo -e "${YELLOW}${prompt}${NC}"
    read -r -p "Overwrite $target? [y/N]: " answer
    case "$answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            echo -e "${YELLOW}Skipped to avoid overwriting $target.${NC}"
            exit 0
            ;;
    esac
}

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: OpenClaw configuration not found at $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Please install OpenClaw first: https://github.com/openclaw${NC}"
    exit 1
fi

require_python3
check_node_version

echo -e "${GREEN}Found OpenClaw configuration${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1: Production Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
ENVIRONMENT="prod"
API_BASE_URL="https://api.bankofai.io/v1"
BASE_URL="${API_BASE_URL}/"
WEB_URL="https://bankofai.io"

echo ""
echo -e "${GREEN}Environment fixed: $ENVIRONMENT${NC}"
echo -e "   Base URL: $BASE_URL"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2: Enter API Key${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Before running this script, please:${NC}"
echo "1. Prepare your BankOfAI API key"
echo "2. API key input below is hidden (no echo)"
echo ""
read -s -p "Enter your BankOfAI API key: " API_KEY
echo ""

if [ -z "$API_KEY" ]; then
    echo -e "${RED}API key cannot be empty. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}API key received${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2.5: Validate API Key & Fetch Models${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
AINFT_API_BASE_URL="$API_BASE_URL" AINFT_API_KEY="$API_KEY" AINFT_MODEL_OUTPUT="$TMP_AINFT_MODEL_FILE" python3 - <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

api_base_url = os.environ["AINFT_API_BASE_URL"].rstrip("/")
api_key = os.environ["AINFT_API_KEY"].strip()
output_file = os.environ["AINFT_MODEL_OUTPUT"]

def post_raw(url, payload, headers=None):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers or {}, method="POST")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.status, dict(resp.headers), resp.read().decode("utf-8", errors="replace")

def get_json(url: str):
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))

def provider_key_for_model(model_id):
    lowered = model_id.lower()
    if lowered.startswith(("gpt-", "o1", "o3", "o4", "text-embedding-", "omni-")):
        return "openai", "OpenAI"
    if lowered.startswith(("claude-",)):
        return "anthropic", "Claude"
    if lowered.startswith(("gemini-", "learnlm-")):
        return "google", "Gemini"
    return "other", "Other"

chat_url = f"{api_base_url}/chat/completions"
validate_payload = {
    "model": "gpt-5-nano",
    "messages": [{"role": "user", "content": "Reply with exactly OK."}],
    "max_tokens": 8,
}
headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json",
}

try:
    status, resp_headers, resp_body = post_raw(chat_url, validate_payload, headers=headers)
    content_type = (resp_headers.get("Content-Type") or "").lower()
    stripped = resp_body.lstrip()
    if status != 200:
        print(f"ERROR: API key validation returned unexpected HTTP {status}.", file=sys.stderr)
        raise SystemExit(1)
    if stripped.startswith("data:") or "text/event-stream" in content_type:
        pass
    elif stripped.startswith("{"):
        json.loads(stripped)
    elif not stripped:
        print("ERROR: API key validation returned an empty response body.", file=sys.stderr)
        raise SystemExit(1)
    else:
        print("ERROR: API key validation returned an unexpected response format.", file=sys.stderr)
        print(stripped[:400], file=sys.stderr)
        raise SystemExit(1)
except urllib.error.HTTPError as exc:
    body = exc.read().decode("utf-8", errors="replace")
    if exc.code == 401:
        print("ERROR: BankOfAI API key is invalid or unauthorized.", file=sys.stderr)
    else:
        print(f"ERROR: API key validation failed with HTTP {exc.code}.", file=sys.stderr)
    if body:
        print(body[:400], file=sys.stderr)
    raise SystemExit(1)
except Exception as exc:
    print(f"ERROR: API key validation failed: {exc}", file=sys.stderr)
    raise SystemExit(1)

try:
    models_resp = get_json(f"{api_base_url}/models")
except Exception as exc:
    print(f"ERROR: Failed to fetch dynamic model list: {exc}", file=sys.stderr)
    raise SystemExit(1)

all_models = []
seen = set()
group_map = {}
for item in (models_resp.get("data") or []):
    model_id = item.get("id") or item.get("name")
    if not model_id or model_id in seen:
        continue
    seen.add(model_id)
    provider_key, title = provider_key_for_model(model_id)
    group = group_map.setdefault(provider_key, {"key": provider_key, "title": title, "models": []})
    model = {"id": model_id, "name": model_id}
    group["models"].append(model)
    all_models.append(model)

groups = [group_map[key] for key in ("openai", "anthropic", "google", "other") if key in group_map]

if not all_models:
    print("ERROR: No models were returned by BankOfAI /models.", file=sys.stderr)
    raise SystemExit(1)

with open(output_file, "w", encoding="utf-8") as f:
    json.dump({"groups": groups, "all": all_models}, f, ensure_ascii=False, indent=2)
PY

echo -e "${GREEN}API key validation passed${NC}"
echo -e "${GREEN}Dynamic model list fetched${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2.6: Write BankOfAI Skill Config${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
mkdir -p "$AINFT_CONFIG_DIR"
if [ -f "$AINFT_CONFIG_FILE" ]; then
    confirm_overwrite "$AINFT_CONFIG_FILE" "Existing BankOfAI config detected."
    AINFT_BACKUP="${AINFT_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$AINFT_CONFIG_FILE" "$AINFT_BACKUP"
    echo -e "${GREEN}Existing BankOfAI config backed up: $AINFT_BACKUP${NC}"
fi
AINFT_API_KEY="$API_KEY" AINFT_BASE_URL="$API_BASE_URL" python3 - <<'PY' > "$AINFT_CONFIG_FILE"
import json
import os

print(json.dumps({
    "api_key": os.environ["AINFT_API_KEY"],
    "base_url": os.environ["AINFT_BASE_URL"],
    "timeout_ms": 15000,
}, ensure_ascii=False, indent=2))
PY
chmod 600 "$AINFT_CONFIG_FILE"
echo -e "${GREEN}BankOfAI skill config written: $AINFT_CONFIG_FILE${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 3: Select Models${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "1) All available models"
echo "2) OpenAI family only"
echo "3) Claude family only"
echo "4) Gemini family only"
echo ""
read -p "Select models [1-4]: " model_choice

case $model_choice in
    1)
        MODELS="$(python3 - "$TMP_AINFT_MODEL_FILE" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print(json.dumps(data.get('all', []), ensure_ascii=False))
PY
)"
        ;;
    2)
        MODELS="$(python3 - "$TMP_AINFT_MODEL_FILE" openai <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
group = next((g for g in data.get('groups', []) if g.get('key') == sys.argv[2]), {})
print(json.dumps(group.get('models', []), ensure_ascii=False))
PY
)"
        ;;
    3)
        MODELS="$(python3 - "$TMP_AINFT_MODEL_FILE" anthropic <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
group = next((g for g in data.get('groups', []) if g.get('key') == sys.argv[2]), {})
print(json.dumps(group.get('models', []), ensure_ascii=False))
PY
)"
        ;;
    4)
        MODELS="$(python3 - "$TMP_AINFT_MODEL_FILE" google <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
group = next((g for g in data.get('groups', []) if g.get('key') == sys.argv[2]), {})
print(json.dumps(group.get('models', []), ensure_ascii=False))
PY
)"
        ;;
    *)
        echo -e "${RED}Invalid choice. Using all models.${NC}"
        MODELS="$(python3 - "$TMP_AINFT_MODEL_FILE" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print(json.dumps(data.get('all', []), ensure_ascii=False))
PY
)"
        ;;
esac

echo ""
echo -e "${GREEN}Models selected${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 4: Set Default Model (Optional)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "Set BankOfAI as default model provider? [y/n]: " set_default

DEFAULT_MODEL=""
if [ "$set_default" = "y" ] || [ "$set_default" = "Y" ]; then
    echo ""
    if command -v python3 &> /dev/null; then
        ENABLED_MODELS=()
        MODEL_LIST_OUTPUT="$(
            python3 - "$MODELS" <<'PY'
import json
import sys
for m in json.loads(sys.argv[1]):
    mid = m.get("id")
    if mid:
        print(f"ainft/{mid}")
PY
        )"
        while IFS= read -r line; do
            [ -n "$line" ] && ENABLED_MODELS+=("$line")
        done <<EOF
$MODEL_LIST_OUTPUT
EOF

        echo "Select default model from enabled models:"
        for i in "${!ENABLED_MODELS[@]}"; do
            idx=$((i + 1))
            echo "$idx) ${ENABLED_MODELS[$i]}"
        done
        custom_idx=$((${#ENABLED_MODELS[@]} + 1))
        echo "$custom_idx) Custom model ID"
        echo ""
        read -p "Select default model [1-$custom_idx]: " default_choice

        if [[ "$default_choice" =~ ^[0-9]+$ ]] && [ "$default_choice" -ge 1 ] && [ "$default_choice" -le "${#ENABLED_MODELS[@]}" ]; then
            DEFAULT_MODEL="${ENABLED_MODELS[$((default_choice - 1))]}"
        elif [ "$default_choice" = "$custom_idx" ]; then
            read -p "Enter custom model ID (e.g., ainft/gpt-5.2): " custom_model
            DEFAULT_MODEL="$custom_model"
        else
            DEFAULT_MODEL="${ENABLED_MODELS[0]}"
        fi
    else
        echo "Recommended models:"
        echo "1) ainft/gpt-5-nano (Recommended)"
        echo "2) ainft/gpt-5-mini"
        echo "3) ainft/claude-sonnet-4-6"
        echo "4) Custom model ID"
        echo ""
        read -p "Select default model [1-4]: " default_choice

        case $default_choice in
            1) DEFAULT_MODEL="ainft/gpt-5-nano" ;;
            2) DEFAULT_MODEL="ainft/gpt-5-mini" ;;
            3) DEFAULT_MODEL="ainft/claude-sonnet-4-6" ;;
            4)
                read -p "Enter custom model ID (e.g., ainft/gpt-5.2): " custom_model
                DEFAULT_MODEL="$custom_model"
                ;;
            *) DEFAULT_MODEL="ainft/gpt-5-nano" ;;
        esac
    fi

    echo ""
    echo -e "${GREEN}Default model: $DEFAULT_MODEL${NC}"
fi

echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 5: Update Configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

confirm_overwrite "$CONFIG_FILE" "OpenClaw config will be updated in place."
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo -e "${GREEN}Backup created: $BACKUP_FILE${NC}"

HAS_MAIN_AGENT_OVERRIDE="$(
    python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        config = json.load(f)
except Exception:
    print("0")
    raise SystemExit(0)

agent_list = ((config.get("agents") or {}).get("list"))
if isinstance(agent_list, list) and any(isinstance(agent, dict) and agent.get("id") == "main" for agent in agent_list):
    print("1")
else:
    print("0")
PY
)"

AINFT_CONFIG_FILE_PATH="$CONFIG_FILE" \
AINFT_PROVIDER_BASE_URL="$BASE_URL" \
AINFT_PROVIDER_API_KEY="$API_KEY" \
AINFT_PROVIDER_MODELS="$MODELS" \
AINFT_DEFAULT_MODEL="$DEFAULT_MODEL" \
python3 - <<'PY'
import json
import os
import tempfile

config_file = os.environ["AINFT_CONFIG_FILE_PATH"]
base_url = os.environ["AINFT_PROVIDER_BASE_URL"]
api_key = os.environ["AINFT_PROVIDER_API_KEY"]
models_json = os.environ["AINFT_PROVIDER_MODELS"]
default_model = os.environ.get("AINFT_DEFAULT_MODEL", "")

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

if "models" not in config or not isinstance(config["models"], dict):
    config["models"] = {}

if "providers" not in config["models"] or not isinstance(config["models"]["providers"], dict):
    config["models"]["providers"] = {}

config["models"]["mode"] = "merge"

provider_models = json.loads(models_json)
config["models"]["providers"]["ainft"] = {
    "baseUrl": base_url,
    "apiKey": api_key,
    "api": "openai-completions",
    "models": provider_models,
}

if "agents" not in config or not isinstance(config["agents"], dict):
    config["agents"] = {}
if "defaults" not in config["agents"] or not isinstance(config["agents"]["defaults"], dict):
    config["agents"]["defaults"] = {}

allowlist = config["agents"]["defaults"].get("models")
if not isinstance(allowlist, dict):
    allowlist = {}

for key in list(allowlist.keys()):
    if isinstance(key, str) and key.startswith("ainft/"):
        del allowlist[key]

for model in provider_models:
    model_id = model.get("id")
    if model_id:
        allowlist.setdefault(f"ainft/{model_id}", {})

config["agents"]["defaults"]["models"] = allowlist

if default_model:
    model_cfg = config["agents"]["defaults"].get("model")
    if not isinstance(model_cfg, dict):
        model_cfg = {}
    model_cfg["primary"] = default_model
    config["agents"]["defaults"]["model"] = model_cfg

    agent_list = config["agents"].get("list")
    if isinstance(agent_list, list):
        for agent in agent_list:
            if isinstance(agent, dict) and agent.get("id") == "main":
                agent["model"] = default_model
                break

config_dir = os.path.dirname(config_file) or "."
fd, temp_path = tempfile.mkstemp(prefix=".openclaw.", suffix=".json", dir=config_dir)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(temp_path, config_file)
except Exception:
    try:
        os.unlink(temp_path)
    except OSError:
        pass
    raise

print("Configuration updated successfully!")
PY
echo -e "${GREEN}Configuration updated${NC}"

echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 6: Restart OpenClaw${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if command -v openclaw &> /dev/null; then
    echo "Restarting OpenClaw gateway..."
    openclaw gateway restart
    echo -e "${GREEN}OpenClaw restarted${NC}"
    if [ -n "$DEFAULT_MODEL" ]; then
        if [ "$HAS_MAIN_AGENT_OVERRIDE" = "1" ]; then
            echo "Setting OpenClaw default model to $DEFAULT_MODEL..."
            if openclaw models set "$DEFAULT_MODEL" >/dev/null 2>&1; then
                echo -e "${GREEN}OpenClaw default model updated${NC}"
            else
                echo -e "${YELLOW}Failed to apply default model via CLI. The config file was updated directly.${NC}"
            fi
        else
            echo -e "${GREEN}Default model saved in config without materializing agents.list.main${NC}"
        fi
    fi
else
    echo -e "${YELLOW}OpenClaw command not found in PATH${NC}"
    echo "Please manually restart OpenClaw gateway:"
    echo "  openclaw gateway restart"
    if [ -n "$DEFAULT_MODEL" ]; then
        if [ "$HAS_MAIN_AGENT_OVERRIDE" = "1" ]; then
            echo "This script updated both agents.defaults.model.primary and agents.list.main.model."
        else
            echo "This script updated agents.defaults.model.primary only."
            echo "No agents.list.main.model was created."
        fi
    fi
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}BankOfAI Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  Environment: $ENVIRONMENT"
echo "  Base URL: $BASE_URL"
echo "  BankOfAI Skill Config: $AINFT_CONFIG_FILE"
if [ -n "$DEFAULT_MODEL" ]; then
    echo "  Default Model: $DEFAULT_MODEL"
fi
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Test your setup:"
if [ -n "$DEFAULT_MODEL" ]; then
    echo "     openclaw agent --agent main --message \"你好\""
else
    echo "     openclaw models set ainft/gpt-5-nano"
    echo "     openclaw agent --agent main --message \"你好\""
fi
echo ""
echo -e "${BLUE}Resources:${NC}"
echo "  BankOfAI API: $API_BASE_URL"
echo "  BankOfAI Web: $WEB_URL"
echo "  Documentation: https://docs.bankofai.io/Openclaw-extension/Setup-use/"
echo ""
echo -e "${GREEN}Happy chatting!${NC}"
echo ""
