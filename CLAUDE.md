# Video Testimonial Tool — Build Instructions for Claude Code

## What this is

A self-hosted alternative to VideoAsk. A single page that:
1. Asks the user for their name + email
2. Walks them through 3 questions one at a time
3. Records video on their phone or laptop using the browser's built-in MediaRecorder API
4. Uploads the final video directly to Cloudflare R2 (object storage)
5. Fires a webhook to GoHighLevel with the contact info + video URL so the contact gets auto-tagged

The user is Michael Rochin, a marketing consultant. He's building this for his client Rotem Sivan (jazz guitarist running fretsfordays.com / rotemsivan.com) to collect 60-second video testimonials from cohort students for a $1,200 course called "Play What You Hear."

## Architecture

```
[User's phone] -> [HTML page on GHL custom page] -> [Cloudflare Worker] -> [Cloudflare R2 bucket]
                                                          |
                                                          v
                                                    [GHL webhook]
```

Three pieces:

1. **`recorder.html`** — single HTML file. Drop into a GHL custom page. Contains all the UI, recording logic, and upload logic. No build step.

2. **`worker.js`** — Cloudflare Worker. Two jobs: (a) issue presigned upload URLs for R2, (b) receive a "recording finished" ping from the browser and forward to GHL webhook. Deployed via `wrangler deploy`.

3. **`wrangler.toml`** — Cloudflare Worker config.

## Setup steps (the human will do these)

### 1. Cloudflare R2

- Sign up for Cloudflare (free)
- Create an R2 bucket (free up to 10GB)
- Create an R2 API token with read/write access to that bucket. Save the access key ID and secret.
- Set CORS on the bucket to allow PUT from his domain (and `localhost` for testing)

### 2. Cloudflare Worker

- Install wrangler: `npm install -g wrangler`
- `wrangler login`
- Edit `wrangler.toml` with his account ID and bucket name
- Set secrets:
  ```
  wrangler secret put R2_ACCESS_KEY_ID
  wrangler secret put R2_SECRET_ACCESS_KEY
  wrangler secret put R2_ACCOUNT_ID
  wrangler secret put R2_BUCKET_NAME
  wrangler secret put GHL_WEBHOOK_URL
  ```
- `wrangler deploy`
- Note the worker URL (e.g. `https://video-testimonial.michael.workers.dev`)

### 3. GoHighLevel

- Create an inbound webhook in GHL (Automations -> Workflows -> new workflow with Inbound Webhook trigger)
- Copy the webhook URL into the Cloudflare secret above
- Build the workflow that follows the webhook trigger: tag contact "testimonial-submitted", send Michael an internal notification email with the video URL, etc.

### 4. Recorder page

- Edit `recorder.html` and set `WORKER_URL` at the top to the Cloudflare Worker URL
- Edit the questions array if needed
- Paste the entire HTML into a GHL Custom Code element on a funnel page
- Done

## Key technical decisions

- **MediaRecorder over file input:** lets the user record in-browser instead of fumbling through their phone's camera roll. Mobile Safari and Chrome both support this.
- **WebM/MP4 format:** Chrome/Android records WebM by default, Safari records MP4. Both work, the worker doesn't transcode — the file extension is set based on what the browser produced.
- **Direct browser-to-R2 upload via presigned URL:** the video never touches the Worker (which has request size limits). Worker only signs the URL.
- **Three questions, one recording per question:** more natural than one long take. Final webhook fires after question 3.
- **No login, no auth on the page:** the contact email they enter is the identifier. GHL handles deduplication.

## What NOT to do

- Don't build a Node/Express backend. The whole point of using Workers is no server to manage.
- Don't transcode videos. R2 just stores whatever the browser uploads. Rotem can play them directly.
- Don't add features not asked for (no analytics dashboard, no email confirmation, no preview/re-record on the page beyond what's already there). Michael wants minimum viable.
- Don't use any framework (no React, no Vue). Single static HTML file.

## File layout

```
video-testimonial-tool/
├── CLAUDE.md           # this file
├── README.md           # human-readable setup guide
├── recorder.html       # the recorder page (paste into GHL)
├── worker.js           # Cloudflare Worker
├── wrangler.toml       # Worker config
└── cors.json           # R2 CORS config (apply via wrangler or dashboard)
```
