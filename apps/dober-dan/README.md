# Dober dan

Slovene learning app for two people. Source and images:
[orazefabian/lang-learn-app](https://github.com/orazefabian/lang-learn-app).

| Component | Image | Notes |
|-----------|-------|-------|
| `webservice` | `ghcr.io/orazefabian/lang-learn-app/app` | Next.js. Runs migrations at boot and the weekly digest in-process. |
| `postgresdb` | `postgres:17-alpine` | Her whole learning history. |
| `piper` | `ghcr.io/orazefabian/lang-learn-app/piper` | Slovene TTS. Voice baked into the image. |
| `whisper` | `ghcr.io/orazefabian/lang-learn-app/whisper` | Slovene ASR. Model downloaded to a PVC on first start. |

Ingress: `dober-dan.halo.fabseit.net`.

## Secrets

Two, neither in git:

```bash
kubectl -n halo create secret generic dober-dan-db-secret \
  --from-literal=POSTGRES_USER=slo \
  --from-literal=POSTGRES_DB=dober_dan \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 32)"

kubectl -n halo create secret generic dober-dan-secret \
  --from-literal=DATABASE_URL="postgres://slo:<that-password>@postgres-dober-dan:5432/dober_dan" \
  --from-literal=SESSION_SECRET="$(openssl rand -base64 48)"
```

`dober-dan-secret` optionally also takes:

- `ANTHROPIC_API_KEY` — the teacher's draft-generation tools. Absent, those
  screens are simply not there.
- `SMTP_URL` and `DIGEST_EMAIL_TO` — emails the weekly digest. Absent, it waits
  in the app.

The deployment carries `reloader.stakater.com/auto`, so adding either later
restarts the pod on its own.

## First run

There is no signup, by design. Create the two accounts once the pod is up:

```bash
kubectl -n halo exec deploy/dober-dan -- env \
  LEARNER_EMAIL=... LEARNER_NAME=... \
  TEACHER_EMAIL=... TEACHER_NAME=... \
  node scripts/seed-users.mjs
```

Passwords are generated and printed once if not supplied. The addresses need a
dotted domain — `fabian@local` is not a valid email address and the script will
refuse it.

Then import the deck and curriculum:

```bash
# Everything lands as draft, pending review in the teacher area.
# Add --activate to skip that and put it straight in her deck.
kubectl -n halo exec deploy/dober-dan -- node scripts/dist/seed-content.mjs
kubectl -n halo exec deploy/dober-dan -- node scripts/dist/generate-cards.mjs

# Generated speech for everything active. Needs Piper up, writes to the media
# volume, so it has to run in the cluster rather than from a laptop.
kubectl -n halo exec deploy/dober-dan -- node scripts/dist/generate-audio.mjs
```

## Updating

Tag a release in the app repo and Renovate opens the PR here:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Three Renovate groups, so an app release is one PR and the speech images are
another: `dober-dan`, `dober-dan-postgres`, `dober-dan-speech`.

Migrations run at boot and are idempotent, so a version bump is just the image
tag. There is no separate migration step.

## Notes

- **Whisper is the expensive one.** `WHISPER_MODEL: medium` on the app and the
  whisper deployment. `small` was tried first and rejected: fed clean synthetic
  Slovene it returned "Mi dva dreva domal" for *Midva greva domov* and "Kvala
  li pa" for *Hvala lepa*. The transcript is shown to her as "verstanden als:
  …", so a wrong one reads as her mistake. `medium` costs ~2 GB resident and
  appreciably longer per phrase on ARM cores; drop back to `small` in both
  places if the node cannot spare it.
- **Both speech services are optional at runtime.** Scale either to zero and
  the app keeps working: no TTS means listening exercises disappear, no ASR
  means speaking falls back to self-assessment. `/api/ready` reports them but
  never fails on them.
- **Two volumes matter.** `pg-dober-dan-data` and `dober-dan-media`, both on
  all three backup schedules. The media volume holds recordings of family
  voices, which is the only part of this that cannot be regenerated. The
  Whisper model PVC is deliberately not backed up — it is a download.
