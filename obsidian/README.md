# Obsidian Docker + MCP Server Setup

Dockerized Obsidian instance with two MCP server integrations for Claude Code.

## Architecture

```
Remote LAN Machine                    Docker Host
+---------------------------+         +-----------------------------------+
| Claude Code               |         | docker-compose (obsidian)         |
|                           |  HTTPS  | +-------------------------------+ |
| obsidian-mcp-server  -----)---------->| Obsidian Local REST API       | |
|   (npx, standalone)       | :27124  | |   port 27123 (HTTP)           | |
+---------------------------+         | |   port 27124 (HTTPS + API key)| |
                                      | +-------------------------------+ |
Docker Host (local)                   | +-------------------------------+ |
+---------------------------+         | | obsidian-mcp-tools plugin     | |
| Claude Code               | docker  | |   embedded MCP server binary  | |
|                           |  exec   | +-------------------------------+ |
| obsidian-mcp-tools  ------)-------->|                                   |
|   (docker exec, in-container)       | UI: ports 3002/3003              |
+---------------------------+         +-----------------------------------+
```

**Two MCP servers, one Obsidian instance:**

| Server | How it connects | Best for |
|--------|----------------|----------|
| **obsidian-mcp-tools** | `docker exec` into container, runs binary directly | Local use on Docker host |
| **obsidian-mcp-server** (cyanheads) | HTTPS to Local REST API on port 27124 | Remote LAN access |

## Prerequisites

1. **Docker host**: `docker-compose.yml` running with the Obsidian container up
2. **Obsidian Local REST API plugin**: Installed and enabled inside Obsidian
   - Access the Obsidian UI at `http://<docker-host>:3002`
   - Go to Settings > Community Plugins > Local REST API
   - Note the API key (or set one)
3. **Ports 27123/27124 accessible** from LAN (no firewall blocking)

## Local Setup (Docker Host)

The Docker host's `~/.config/claude/config.json` has both servers configured:

```json
{
  "mcpServers": {
    "obsidian-mcp-tools": {
      "command": "docker",
      "args": [
        "exec", "-i", "obsidian",
        "/config/config/claude/.obsidian/plugins/mcp-tools/bin/mcp-server"
      ],
      "env": {
        "OBSIDIAN_API_KEY": "<your-api-key>"
      }
    },
    "obsidian-mcp-server": {
      "command": "npx",
      "args": ["-y", "obsidian-mcp-server"],
      "env": {
        "OBSIDIAN_API_KEY": "<your-api-key>",
        "OBSIDIAN_BASE_URL": "https://localhost:27124",
        "OBSIDIAN_VERIFY_SSL": "false"
      }
    }
  }
}
```

## Remote LAN Setup

Follow these steps to connect from another machine on the same LAN.

### Step 1: Find the Docker host's LAN IP

On the Docker host, run:

```bash
ip -4 addr show | grep 'inet ' | grep -v '127.0.0.1'
```

Note the IP (e.g., `192.168.1.100`).

### Step 2: Verify port reachability

From the remote machine, test that the REST API is accessible:

```bash
# Test HTTP (insecure, no auth required)
curl http://<docker-host-ip>:27123

# Test HTTPS (self-signed cert, requires API key)
curl -k -H "Authorization: Bearer <your-api-key>" \
  https://<docker-host-ip>:27124
```

You should get a JSON response. If you get a connection error, check the Docker host's firewall:

```bash
# On the Docker host (if using ufw)
sudo ufw allow from 192.168.1.0/24 to any port 27123:27124 proto tcp
```

### Step 3: Install Node.js (if needed)

obsidian-mcp-server requires Node.js >= 18:

```bash
node --version  # should be >= 18
```

### Step 4: Configure Claude Code on the remote machine

Edit `~/.config/claude/config.json` on the remote machine:

```json
{
  "mcpServers": {
    "obsidian-mcp-server": {
      "command": "npx",
      "args": ["-y", "obsidian-mcp-server"],
      "env": {
        "OBSIDIAN_API_KEY": "<your-api-key>",
        "OBSIDIAN_BASE_URL": "https://<docker-host-ip>:27124",
        "OBSIDIAN_VERIFY_SSL": "false"
      }
    }
  }
}
```

Replace `<docker-host-ip>` with the IP from Step 1 and `<your-api-key>` with the Local REST API plugin's API key.

### Step 5: Restart Claude Code

Restart Claude Code (or start a new session) to pick up the new MCP server config. The obsidian-mcp-server tools will appear as `mcp__obsidian-mcp-server__*`.

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OBSIDIAN_API_KEY` | Yes | — | API key from Local REST API plugin |
| `OBSIDIAN_BASE_URL` | No | `https://127.0.0.1:27124` | Full URL to the REST API |
| `OBSIDIAN_VERIFY_SSL` | No | `true` | Set `false` for self-signed certs |
| `OBSIDIAN_ENABLE_CACHE` | No | `true` | Enable vault file caching |
| `OBSIDIAN_CACHE_REFRESH_INTERVAL_MIN` | No | `10` | Cache refresh interval (minutes) |
| `MCP_TRANSPORT_TYPE` | No | `stdio` | Transport type (`stdio` or `http`) |

## Available Tools

### obsidian-mcp-server (cyanheads) — 8 tools

| Tool | Description |
|------|-------------|
| `obsidian_read_note` | Read note content by path |
| `obsidian_update_note` | Append, prepend, or overwrite note content |
| `obsidian_search_replace` | Find and replace within a note |
| `obsidian_global_search` | Vault-wide text search |
| `obsidian_list_notes` | List notes in a folder |
| `obsidian_manage_frontmatter` | Read/write YAML frontmatter |
| `obsidian_manage_tags` | Add/remove/rename tags |
| `obsidian_delete_note` | Delete a note |

### obsidian-mcp-tools (jacksteamdev) — vault access tools

| Tool | Description |
|------|-------------|
| `get_server_info` | Check REST API connectivity |
| `get_active_file` / `update_active_file` | Read/write the currently open file |
| `list_vault_files` / `get_vault_file` | Browse and read vault files |
| `create_vault_file` / `delete_vault_file` | Create and delete files |
| `patch_vault_file` / `append_to_vault_file` | Modify file content |
| `search_vault` / `search_vault_simple` / `search_vault_smart` | Search the vault |
| `show_file_in_obsidian` | Open a file in the Obsidian UI |
| `execute_template` | Run Templater templates |

## Troubleshooting

### Connection refused from remote machine
- Verify the container is running: `docker ps | grep obsidian`
- Check ports are bound to `0.0.0.0` (not `127.0.0.1`): `docker port obsidian`
- Check firewall rules on the Docker host

### SSL certificate errors
- Set `OBSIDIAN_VERIFY_SSL=false` — the Local REST API uses a self-signed certificate
- Alternatively, use the HTTP endpoint (`http://<ip>:27123`) by changing `OBSIDIAN_BASE_URL`

### API key rejected
- Verify the key matches what's configured in Obsidian's Local REST API plugin settings
- Access the Obsidian UI at `http://<docker-host>:3002` to check the plugin config

### MCP server not appearing in Claude Code
- Restart Claude Code after editing `config.json`
- Check `config.json` is valid JSON (no trailing commas)
- Verify `npx` is on your PATH and Node.js >= 18 is installed

### Both servers showing duplicate data
- This is expected — both servers access the same vault via the same REST API
- Use whichever server's tool interface you prefer for each operation
