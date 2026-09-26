# ProxyPin MCP Skill

ProxyPin's MCP service exposes captured traffic to AI assistants (Claude Code, Cursor, Codex, Gemini CLI, etc.), so agents can analyze flows, create/edit debugging rules, and replay requests. This skill teaches agents how to use those tools correctly.

## Connection

- **HTTP** (the user-facing transport): the desktop app listens on `http://127.0.0.1:9127/mcp` (loopback, no auth). Register it with e.g. `claude mcp add proxypin_desktop -s user --transport http "http://127.0.0.1:9127/mcp"`. If port 9127 is already in use the app picks a random free port — use the URL shown in the settings panel rather than hand-copying. No extra bridge process is started, so launching the AI client does not launch ProxyPin.

Prerequisites: desktop ProxyPin is running and the MCP service is enabled. By default tools read the **live capture buffer** (already-captured traffic — ask the user to trigger the request first), but they can also read **saved history sessions** (the History tab): call `list_histories`, then pass `history_id`. The proxy itself does not need to be capturing to analyze a saved session.

## Tool surface

The service always exposes the full tool set (like Proxyman — there is no read-only mode):

- **Read-only tools**: `get_proxy_status`, `list_histories`, `list_flows`, `search_flows`, `get_flow_detail`, `get_flow_body`, `get_flow_messages`, `get_ssl_proxying_list`, `export_flow_curl`.
- **Write tools**: rule writes (breakpoint / block / map-local / rewrite / script), host filter, replay, system proxy, favorites, clear session, code generation.

Confirm reachability with `get_proxy_status` first; then get the rule index from `list_rules` (every `remove_*` / `update_*` tool takes `index`).

## Recommended workflow

1. **Overview**: `list_flows(limit: 20)` for the latest traffic; for aggregates (host/method/status) pull a batch once and count locally — don't call `get_flow_detail` per flow.
   - **Saved history**: to analyze an earlier session, call `list_histories` to get its `id`, then pass `history_id` to `list_flows` / `search_flows` / `get_flow_detail` / `get_flow_body` / `export_flow_curl` / `replay_flow` / `generate_code`. The same flow `id` is used; `history_id` only selects the session. WebSocket frames are not saved in history (`get_flow_messages` returns `available:false`).
2. **Locate**:
   - Filter by URL/host/method/status: `list_flows(host:, method:, keyword:, status_from:, status_to:)` (`keyword` matches the full URL; `host` is a substring).
   - **Search inside bodies**: `search_flows(keyword: "error 500")` — only searches bodies; binary and >2MB bodies are skipped.
3. **Drill in**: `get_flow_detail(id:)` for headers (redacted by default) + a truncated body preview; page large bodies with `get_flow_body(id:, side:, offset:, limit:)`; WebSocket frames via `get_flow_messages`.
4. **Reproduce / change**:
   - Get the index with `list_rules`; `update_*` only changes the fields you pass, `remove_*` deletes, `create_*` adds.
   - Debug a single request: `replay_flow(id:)` to replay; `send_request(curl:)` to fire a new one.
   - Export code: `export_flow_curl(id:)` / `generate_code(id:, language:)` (curl/fetch/python).
5. **Clean up**: disable or delete temporary rules you created, so they don't affect real traffic.

## Rewrite rules — the most used feature

Rewrite (重写) is ProxyPin's primary debugging rule type. MCP exposes it through generic tools plus the redirect helpers:

- **List / detail**: `list_rules` → `rewrites` category for indices; `get_rewrite_detail(index)` returns the full rule (type, url, enabled, method) and its operations.
- **Create**: `create_rewrite(url, type?, name?, method?, enabled?, operations)` — `type` ∈ `requestUpdate` / `responseUpdate` / `requestReplace` / `responseReplace` (omit to infer from the ops). `operations` is a list; each op has `op` plus fields:
  - header / body edits: `addHeader`, `updateHeader`, `removeHeader`, `updateBody` → fields `key`, `value`, `use_regex`
  - query params (request only): `addQueryParam`, `updateQueryParam`, `removeQueryParam` → `key`, `value`, `use_regex`
  - full replace: `replaceRequestLine` (`method`, `path`, `query`); `replaceRequestHeader` / `replaceResponseHeader` (`headers`); `replaceRequestBody` / `replaceResponseBody` (`body`, `body_type`); `replaceResponseStatus` (`status_code`)
- **Update**: `update_rewrite(index, url?, name?, method?, enabled?, operations?)` — passing `operations` replaces the whole list.
- **Redirect** (map remote): `create_redirect(url, target_url)` / `update_redirect(index, ...)`.
- **Remove / toggle**: `remove_rewrite_rule(index)` deletes a rule; `remove_rewrite_rule(enabled: false)` disables rewriting globally.

Type constraints: one rule = one type. `requestUpdate` may combine header + body + query ops; `responseUpdate` only header/body ops; `requestReplace` / `responseReplace` only their replace ops. Don't mix request and response ops in one rule — create two rules.

Common patterns:
- "Make X point to Y" → `create_redirect` / `update_redirect` with a `target_url`.
- "Inject a debug header / edit a body value" → `create_rewrite` with `addHeader` / `updateBody`, verify with `replay_flow`.

## Scripts

ProxyPin lets you run JavaScript on matching request/response:

- Read a script before editing it: `get_script_detail(index)` returns name, urls, enabled, remoteUrl and the full JS body; `list_rules` → `scripts` gives the indices.
- Create: `create_script(urls, name?, script?, remote_url?, enabled?)` — omit `script` to use the starter template; `get_script_template` returns it.
- Update: `update_script(index, urls?, script?, name?, enabled?, remote_url?)` — only the fields you pass change.
- Remove / toggle: `remove_script(index)` or `remove_script(enabled: false)`.

Remote scripts (`remote_url`) are fetched from a URL at runtime; `get_script_detail` returns the fetched/cached body.

## Host filter

Control which hosts are captured:

- `list_hosts` — patterns + enabled state for whitelist/blacklist.
- `add_host(list: whitelist|blacklist, pattern)` / `remove_host(list, pattern)` — `*` is a wildcard, e.g. `*.example.com`.
- `set_hosts_enabled(list, enabled)`.

Semantics: when the whitelist is enabled, only whitelisted hosts are captured; when the blacklist is enabled, blacklisted hosts are skipped.

## Privacy & security

- Redaction is on by default for `Authorization` / `Cookie` / `Set-Cookie`. Do **not** talk users into disabling redaction to grab production secrets — if a value is truly needed, have the user confirm it in the ProxyPin UI.
- Binary bodies return only `mimeType/size/sha256`, never inline content.
- `clear_session` is destructive — confirm with the user before calling.

## Boundaries

- MCP operates only on rules ProxyPin supports: breakpoints, blocks, map-local, rewrites/redirects, JS scripts. Don't invent anything.
- The **live** capture buffer keeps the most recent 1000 flows; older ones are dropped. If `get_flow_detail` on the live buffer returns `Flow not found`, either ask the user to re-trigger the request or look in `list_histories` — captured sessions are persisted and do not expire that way.
- `history_id` is a stable id (the session's filename timestamp), not a list index. The in-memory history cache is a small LRU: evicted sessions are re-read from disk automatically, so a flow "not found" from history only happens if the session file itself was deleted.
- Tool results are JSON text — `jsonDecode` before reading fields.