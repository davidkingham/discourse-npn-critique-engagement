# discourse-npn-critique-engagement

Critique engagement scoring, recognition, and moderation tools for Nature
Photographers Network. One score, three surfaces: smarter moderation, private
motivation, public recognition.

## What it does

- **Rolling nightly scoring** — a scheduled job scores every member active in
  the critique category (and its subcategories) over the trailing window
  (`npn_critique_window_days`, default 90): critiques weighted by substance
  (length tiers after quote-stripping, capped like bonus, discounted
  follow-ups) balanced against photos posted. One row per member; nothing
  resets — contributions age out of the window naturally. On the 1st, a
  monthly snapshot records each member's standing for badges, trends, and
  history.
- **Recognition chips** — currently-Excellent members ("Critique Guide") and
  permanent-badge holders ("Critique Steward") get a labeled chip next to
  their name on every post and on the user card. Positive signals only;
  `npn_critique_chip_min_tier` can extend chips to Healthy members.
- **Rising Critic** (`npn_critique_rising_enabled`) — each month, the most
  generous new-member critic earns a one-time badge, a distinctly styled
  spotlight chip for the following month, a mention in the highlights topic,
  a congratulations PM, and a permanent place on the hall of fame. Quiet
  months award nobody.
- **Award reactions** — reactions listed in `npn_critique_award_reactions`
  (from discourse-reactions) add a capped bonus to the critique they land on,
  with extra weight when the award comes from the topic owner. Awards
  received show on the private impact panel and the admin report. Degrades
  gracefully when discourse-reactions is not installed.
- **Staff surface** — tier + score on the user card (staff only), an admin
  report with trend arrows and tier filtering, a category health dashboard,
  and the moderator tools under `/moderate` (see below).
- **Private member surface** — "Your critique impact" on the member's own
  profile: current tier, weighted critique count, ratio, one concrete next
  action, badge progress, and month-by-month history. Never visible to anyone
  else.
- **Public surface** — monthly leaderboard (`/critique-engagement/leaderboard`),
  hall of fame (`/critique-engagement/hall-of-fame`), three recognition badges
  with flair groups, a pinned season-close winners topic, and a dismissible
  give-and-take composer reminder. No public surface ever shows a low tier or
  a raw score.

## Moderator tools (`/moderate`)

All staff-only. The dashboard at `/moderate` gathers everything a moderator
triages: images still waiting for a substantive critique (new members first),
posts in the New Members category that need more replies, this week's pick
board, and the top of the outreach and welcome queues.

### Editors' picks (`/moderate/editors-picks`)

The weekly pick queue: one Sunday-anchored week of images with each poster's
engagement standing beside them.

- **Defaults to the last finished week** — moderators pick after a week
  closes, so with no explicit week the queue opens on the week that just
  ended, not the empty one that just started.
- **Poster context on every card** — the poster's give-and-take standing
  (tier, score, photos shared, threads critiqued) sits beside each image,
  along with how many of their images became Editors' Picks in the last 12
  months, a signal moderators use when judging.
- **Week and genre live in the URL** (`?week=YYYY-MM-DD&tag=birds`), so the
  browser back button, bookmarks, and links shared between moderators land on
  the same view. The genre dropdown always offers the full genre vocabulary,
  even genres with no posts that week.
- **Picking** declares which genre the pick fills (tags overlap; the
  declaration doesn't) and can include a public reason that becomes the pick
  note's body. With `npn_critique_pick_finalize_minutes` set, picks are
  staged with an undo window before anything member-visible happens; on
  finalize the topic is tagged, a small-action note is posted, the badge is
  granted, and a congratulations PM goes out. Picks can also be made from a
  post's admin menu.
- **A hand-added tag is recoverable** — a pick counts as real only once its
  moderator note exists (matching how the dashboard board counts picks), so a
  topic that only carries the pick tag someone added by hand shows as
  "tagged, not picked" with the Pick button kept. One click finalizes it —
  the already-present tag is a harmless no-op, and the note, badge, genre,
  and PM all follow. (The member feed still treats the tag as the source of
  truth, so a hand-tagged image surfaces to members immediately either way.)
- **"No pick this week"** — on the dashboard board a moderator can declare a
  deliberate no-pick for a genre when nothing strong enough was posted. It
  shows as a judged empty slot, distinct from a slot nobody got to, resets
  each Sunday like picks, and is superseded by an actual pick.

### Outreach (`/moderate/outreach`)

Two queues with opposite valences: priority-outreach members (posting far
more than they give) and promising new members to welcome (already giving).
Each row shows the member's genres, standing, and a shared contact log.

- **Claims** — "I'll reach out" marks a member as taken so two moderators
  don't write the same person. The claimer gets one reminder PM
  (`npn_critique_claim_reminder_hours`) and stale claims expire
  (`npn_critique_claim_expiry_days`).
- **Sending the member a PM completes the claim automatically** — the
  contact is logged with the PM's title and the claim clears. Welcoming in a
  thread instead still needs the contact logged by hand (a thread reply is
  too ambiguous to auto-detect).
- **Copy template** — each row offers starting-point DM texts (welcome,
  invite to critique, softer hello, follow-up) with usernames pre-filled and
  bracketed spots for the personal parts. The texts are locale strings
  (`npn_critique_engagement.admin.outreach.templates`), editable under
  Admin > Customize > Text.

## Setup

1. Enable `npn critique engagement enabled` and set `npn critique category`.
2. Wait for (or trigger) the `Jobs::NpnCritiqueScoresRefresh` nightly job.
3. Optional: enable badges (`npn critique badges enabled`), create/select the
   two flair groups, enable the nudge banner and the season-close topic.

Every formula parameter, tier boundary, and badge threshold is a site setting
(prefix `npn_critique_`).

## Formula provenance

The scoring formula is ported directly from the tuned Data Explorer prototype
(July 2026): the aggregation lives in
`DiscourseNpnCritiqueEngagement::Scorer::AGGREGATES_SQL`, the scoring branches
in `DiscourseNpnCritiqueEngagement::Formula.score` (Ruby, so the private
panel can simulate "N more critiques reaches Healthy" with the exact curve).
The critique category is scoped together with its subcategories.

One deliberate difference: the prototype scored a rolling 3-month window,
while the plugin scores calendar months (spec §9). Tier boundaries were
calibrated on the 3-month run and should be re-validated against a monthly
window before launch — they are all site settings.
