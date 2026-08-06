# SpaceSlim — Product Overview

**Tagline:** Free up space without losing your memories.

**One‑liner:** SpaceSlim is a private, on‑device storage cleaner for iPhone that
compresses large videos, finds photos worth removing (similar, duplicate,
blurry), and hides sensitive media in an encrypted, Face‑ID‑locked vault — with
nothing ever leaving your device.

---

## What It Is

SpaceSlim helps you reclaim iPhone storage in three complementary ways:

1. **Compress** — shrink large videos while keeping them (quality preserved).
2. **Clean** — review and delete media you don't need, grouped into smart
   categories.
3. **Hide** — move private photos and videos into an encrypted Private Vault.

Everything runs **100% on your device**. There is no account, no sign‑up, no
cloud, no uploads, and no tracking.

---

## Key Features

### 1. Storage Dashboard
- A clear "Reclaimable" ring showing how much space you can get back.
- Two paths, side by side: **Compress** (keep everything) vs **Clean** (remove junk).
- Live device‑usage readout (GB used of total).
- Pull‑to‑refresh to rescan on demand.

### 2. Smart Cleanup by Category
On‑device analysis (Apple Vision) classifies your library so you can clean fast:
- **Similar** photos — near‑duplicate shots grouped together.
- **Duplicates** — exact copies.
- **Blurry photos** — out‑of‑focus shots (Laplacian sharpness).
- **Portraits** — photos containing people (face detection).
- **Large videos**, **Screenshots**, **Live Photos**, **Screen recordings**.

For grouped results, SpaceSlim recommends the **"Best" photo to keep** and
pre‑selects the rest for removal — so cleaning a burst is one tap.

### 3. Video Compression
- Choose quality (High / Balanced / Small) and frame rate.
- See an estimated before/after size and total savings.
- Optionally **replace originals** after the compressed copy is saved.
- Live progress and a friendly result summary.

### 4. Private Vault
- Move photos/videos out of the Photos app into a hidden, in‑app vault.
- Contents are **encrypted at rest with AES‑256‑GCM**; the key lives in the
  device **Keychain** and never leaves the device.
- Unlocked with **Face ID / Touch ID / passcode**.
- Originals are removed from Photos so they're truly hidden; you can **restore**
  them to Photos anytime.

### 5. Safe by Design
- Deletions go through the system's own confirmation and land in **"Recently
  Deleted" (recoverable for 30 days)**.
- The dashboard updates instantly after you delete — no stale numbers.
- Works with **Limited Photo Access** and offers a quick "Select more" path.

---

## Why SpaceSlim (vs. typical cleaners)
- **Truly private:** on‑device only, no account, no uploads, no analytics.
- **Two jobs, one app:** compress to keep memories *and* clean to remove junk —
  most cleaners only delete.
- **Differentiated Vault:** encrypted, Face‑ID‑gated hidden album.
- **Polished, modern UI:** consistent glass/gradient design, light & dark.

---

## How It Works (Privacy)
1. You grant Photo access.
2. SpaceSlim scans and classifies your library **locally** (no image leaves the
   device).
3. You decide what to compress, delete, hide, or restore — every destructive
   action is confirmed by the system.

See `PRIVACY_POLICY.md` and `TERMS_OF_SERVICE.md` in this folder.

---

## Technical Highlights
- SwiftUI, iOS. On‑device ML via **Vision** (image feature prints for
  similarity/duplication, face detection for portraits).
- Concurrent, order‑preserving scan pipeline for speed on large libraries.
- AES‑256‑GCM encryption (CryptoKit) + Keychain‑stored key for the vault.
- LocalAuthentication (Face ID / passcode) gating.
- Memoized, lazy grids for smooth scrolling with thousands of items.

---

## Localization
English (base) plus **Arabic, German, Spanish, French, Hindi, Italian,
Japanese, Korean, Portuguese** (via a String Catalog). More can be added easily.

---

## Requirements
- iPhone running a recent version of iOS.
- Photo Library access (required for scanning, compressing, and cleaning).

---

## App Store Copy (suggested)

**Subtitle:** Compress, clean & hide — 100% private

**Promotional text:**
Reclaim gigabytes in minutes. Compress big videos, clear out similar/duplicate/
blurry photos, and lock private media in an encrypted vault — all on your device,
nothing uploaded.

**Keywords:** storage, cleaner, free up space, compress video, duplicate photos,
similar photos, blurry, private vault, hide photos, clean up.

---

_This document is for product and marketing reference. Replace placeholder
contact details in the legal documents before publishing._
