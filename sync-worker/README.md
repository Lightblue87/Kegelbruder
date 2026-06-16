# Kegel Brueder PWA Sync Worker

Tiny Cloudflare Worker backend for the installed PWA. It stores one SQLite
snapshot per club in Cloudflare KV and protects access with a shared secret.

## Setup

1. Install Wrangler and log in:

   ```sh
   npm install -g wrangler
   wrangler login
   ```

2. Create a KV namespace:

   ```sh
   wrangler kv namespace create KBG_SYNC
   ```

3. Copy `wrangler.toml.example` to `wrangler.toml` and paste the namespace ID.

4. Store the shared sync key:

   ```sh
   wrangler secret put SYNC_SECRET
   ```

5. Deploy:

   ```sh
   wrangler deploy
   ```

6. In the PWA settings, enter:

   - Sync-Endpunkt: the deployed Worker URL, for example `https://kegelbrueder-sync.<account>.workers.dev`
   - Club-ID: `kegelbrueder`
   - Sync-Schluessel: the same value stored as `SYNC_SECRET`

## Sync Model

The PWA remains fully offline-first. Each iPad works against its local SQLite
database in IndexedDB. Synchronisation is manual:

- `Status pruefen`: checks the remote revision.
- `Dieses Geraet hochladen`: uploads this iPad's current SQLite snapshot.
- `Remote laden`: replaces this iPad's local database with the remote snapshot.

Uploads include the last known remote revision. If another device uploaded a
newer revision first, the Worker returns `409 Conflict`; the app then asks the
user to load the remote state before uploading again. This avoids silent data
loss from competing iPads.
