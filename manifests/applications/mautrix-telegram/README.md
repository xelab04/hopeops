# mautrix-telegram relay — `#cloudnative-general:meetup.mu` ↔ Telegram General topic

Go (bridgev2) puppeting/relay bridge linking the Matrix room
`#cloudnative-general:meetup.mu` (homeserver `meetup.mu`, continuwuity deployment
in `manifests/applications/matrix-meetup`) to the **General topic** of the
Cloud Native MU Telegram supergroup (chat `2184238329` / `-1002184238329`).

Replaces the old `matterbridge` setup (archived to `manifests/archive/matterbridge`;
42wim/matterbridge is unmaintained). Chosen because it is actively maintained,
supports Telegram forum topics, and works with Conduit-family homeservers.

## Files in this directory

| File                 | Purpose |
|----------------------|---------|
| `config.yaml`        | ConfigMap `mautrix-telegram`: non-secret bridge config (see notes below). |
| `deploy.yaml`        | Deployment. Calls `/usr/bin/mautrix-telegram` directly; see gotchas. |
| `svc.yaml`           | ClusterIP Service `mautrix-telegram:29317` (appservice listener). |
| `secret-example.yaml`| Commented template. Copy to `secret.yaml`, fill in, apply manually. |
| `secret.yaml`        | **Real secrets. Git-ignored, never commit.** |
| `registration.yaml`  | Appservice registration generated during setup. **Git-ignored, never commit.** |
| `.gitignore`         | Ignores `secret.yaml`, `registration.yaml`, `temp.yaml`. |

Secrets reach the bridge as `MAUTRIX_*` env overrides (double underscore =
nesting, e.g. `MAUTRIX_APPSERVICE__AS_TOKEN`). `env_config_prefix: MAUTRIX_`
is set in the ConfigMap. Related DB objects live in
`manifests/system/cnpg/{databases,databaseroles}.yaml` (`mautrix-telegram`
database + role; password lands in secret `mautrix-telegram-db-password`, ns `cnpg`).
Argo Application: `argo/applications/mautrix-telegram.yaml` (namespace `matrix-meetup`).

## Setup steps (in order)

1. **Database.** `kubectl apply -f manifests/system/cnpg/databases.yaml -f
   manifests/system/cnpg/databaseroles.yaml`, wait for the role, read the password:
   `kubectl -n cnpg get secret mautrix-telegram-db-password -o jsonpath='{.data.password}' | base64 -d`
2. **Telegram API credentials.** Create an app at https://my.telegram.org/apps
   (any title, platform Other) → `api_id` (number) + `api_hash`. Required even
   for bot logins — the bridge is an MTProto client, the BotFather token alone
   is not enough.
3. **Telegram bot.** @BotFather → `/newbot` → save the token. Bot Settings →
   Group Privacy **off**, groups allowed. Add `@<bot>` as **admin** of the
   supergroup. Post a message in the General topic (bot logins only discover
   chats *after* receiving a message).
4. **Appservice tokens.** `openssl rand -hex 32` twice → `AS_TOKEN`, `HS_TOKEN`.
   Write `registration.yaml` (use `secret-example.yaml` header + this body):
   ```yaml
   id: telegram   # MUST match appservice.id in config.yaml
   url: http://mautrix-telegram:29317
   as_token: <AS_TOKEN>
   hs_token: <HS_TOKEN>
   sender_localpart: telegrambot
   namespaces:
     users:
       - exclusive: true
         regex: '@telegram_.*'
     aliases: []
     rooms: []
   rate_limited: false
   de.sorunome.msc2409.push_ephemeral: true
   ```
5. **Bridge secret.** Copy `secret-example.yaml` → `secret.yaml`, fill
   `AS_TOKEN`/`HS_TOKEN` (step 4), `API_ID`/`API_HASH` (step 2), `DATABASE_URI`
   (`postgres://mautrix-telegram:<pw-from-step-1>@main-postgres-rw.cnpg.svc.cluster.local:5432/mautrix-telegram?sslmode=require`),
   `PROVISIONING_SECRET` (`openssl rand -hex 16`), `PICKLE_KEY`
   (`openssl rand -base64 48`; pre-generate — the config mount is read-only so
   the bridge can't persist an auto-generated one).
   `kubectl -n matrix-meetup apply -f secret.yaml`.
6. **Config admin placeholder.** Replace `@admin:meetup.mu` under
   `bridge.permissions` in `config.yaml` with your real MXID (alex:meetup.mu).
7. **Deploy.** Commit, push, sync the `mautrix-telegram` Argo app. Expect
   `as_token`-related crash-looping until step 8 — normal.
8. **Register appservice.** In the Matrix `#admins` room:
   `!admin appservices register` + full `registration.yaml` in a code block.
   Verify with the list command (expect `Appservices (1): telegram`). Same ID
   replaces the previous registration. Bridge logs should then show
   `Bridge started` instead of `as_token was not accepted`.
9. **Relay Matrix account.** Don't use your personal account (see relay quirks).
   Create a dedicated user — open registration is **unavailable** on stock
   continuwuity builds (see gotchas), so in `#admins`: `!admin users create`
   → e.g. `@telegramrelay:meetup.mu`. Log into Element as that user.
10. **Log in.** In the relay account's DM with `@telegrambot:meetup.mu`
    (commands here take **no** prefix): `login bot <botfather-token>`,
    then `list-logins` (note the login ID).
11. **Invite** `@telegrambot:meetup.mu` to `#cloudnative-general` and promote it
    to **Moderator** (needs 50+ for `m.bridge` state events).
12. **Link rooms.** In `#cloudnative-general` (prefixed — non-management room):
    `!tg bridge channel:2184238329` (full portal ID **with** the `channel:`
    prefix; bare numbers are not found). Then `!tg set-relay` in the same room
    if relay formatting is missing.
13. **Verify.** Telegram General → Matrix and back; one reply in a non-General
    topic to confirm thread mapping.

## Command cheat-sheet

- Bot DM (management room): **no prefix** — `help`, `login bot <token>`,
  `list-logins`, `logout`, `sync-chats`.
- Any other room: **`!tg` prefix** — `!tg bridge channel:<id>`,
  `!tg set-relay [login-ID]`, `!tg id` (shows what a portal room is bridged to),
  `!tg delete-portal` (admin, removes stray portal rooms).
- Server admin (`#admins`): `!admin appservices register/list/unregister`,
  `!admin users create`, `!admin token issue/list/revoke`.

## Behavior notes (limits, not bugs)

- **Telegram side: names yes, avatars never.** Telegram bots send as one fixed
  identity — no webhook-style impersonation like Discord. Relay prepends
  `<b>Name</b>:` to message text. Matrix side is unaffected: Telegram users
  appear as full ghost puppets with names + avatars.
- **Login owner bypasses the relay.** Whoever ran `login` gets no relay
  formatting on their own messages (they arrive as the bare bot identity).
  Hence the dedicated `@telegramrelay` account.
- **General topic ↔ room timeline; other topics ↔ Matrix threads.**
- **Bot logins sync chats lazily** — a chat is unknown until a message arrives
  while logged in (`No portal found … receive a message first`). Bot must be
  group admin (or privacy off) and a fresh message must post-login-date it.
- Telegram chat IDs in bridge commands: plain positive integer **with**
  type prefix for portals (`channel:2184238329`); the `-100` Bot-API prefix
  is never used.

## Gotchas hit during setup (read before debugging)

1. **`exec: "-c": executable file not found`.** Image `CMD` is `/docker-run.sh`
   (interactive first-run helper); our `args` overrode it. Fix: explicit
   `command: ["/usr/bin/mautrix-telegram"]` in `deploy.yaml`.
2. **Config rewrite vs read-only mount.** Bridge rewrites `config.yaml` at
   startup → ConfigMap mount is read-only → crash. Fix: ConfigMap mounts at
   `/config-template`, initContainer copies to writable `emptyDir` at `/config`.
3. **`Failed to parse environment variables: telegram_service_host`.**
   Kubernetes injects `MAUTRIX_TELEGRAM_SERVICE_HOST/PORT` from our own
   Service, and `env_config_prefix: MAUTRIX_` makes the bridge parse them as
   config. Fix: `enableServiceLinks: false` in the pod spec.
4. **`as_token was not accepted`.** Checklist: registration `id` must equal
   config `appservice.id` (`telegram`); tokens must match **exactly** on both
   sides (re-register replaces by ID); bridge must talk to the same server
   you registered on (`http://matrix-continuwuity:6167`). After any token
   rotation you must re-register — old registrations keep old tokens.
5. **`m.bridge events: insufficient permissions`.** Promote `@telegrambot` to
   Moderator (50+) in the target room; `--ignore-permissions` exists but drops
   bridge-info state.
6. **Command ran in the wrong room.** `bridge` sent in the bot DM creates a
   *new* portal room + invite instead of linking the current room. Link
   commands go in the target room.
7. **Continuwuity: no open registration on stock builds.** The
   `yes_i_am_very_very_sure…` flag only works with the `openreg` compile-time
   feature, which published images lack — `M_FORBIDDEN` regardless of flags.
   Create users via `!admin users create`, hand out `!admin token issue`
   invite tokens. (Bonus: that *is* per-account signup validation.)
8. **Cosmetic log noise, safe to ignore:** `unsupported channel membership
   change type invite -> join`, `Failed to redact command` /
   `Failed to send welcome message` (bot underpowered in auto-created rooms),
   one-off `Homeserver -> appservice … Connection refused` ping race at
   startup, `/sync … connection refused` lines from before a homeserver restart.

## Operational notes

- **Secrets hygiene (learned the hard way).** A filled secrets file was once
  committed and pushed via careless `git add -A`. Only `secret-example.yaml`
  belongs in git; `secret.yaml`, `registration.yaml` are gitignored. Never
  `git add -A` / commit / push without checking `git status` first. If a leak
  happens: rotate the tokens (new `AS/HS` → patch live secret → rewrite
  `registration.yaml` → re-register → restart bridge), delete local copies.
- **Image pinning.** Currently `dock.mau.dev/mautrix/telegram:latest` (was
  `v26.09+dev` at setup). Pin to a release tag once stable; watch Renovate.
- **Retire matterbridge leftovers** after verifying relay:
  `kubectl -n matrix-meetup delete deploy/matterbridge secret/matterbridge-config`
  (app-of-apps has `prune` disabled, so Argo won't remove them).
- **Keep `default_relays: []`** until the relay login ID is known; optionally
  set it to the login ID later so future `bridge` calls pick it up implicitly.
