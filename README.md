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
  and an outreach queue with a shared contact log.
- **Private member surface** — "Your critique impact" on the member's own
  profile: current tier, weighted critique count, ratio, one concrete next
  action, badge progress, and month-by-month history. Never visible to anyone
  else.
- **Public surface** — monthly leaderboard (`/critique-engagement/leaderboard`),
  hall of fame (`/critique-engagement/hall-of-fame`), three recognition badges
  with flair groups, a pinned season-close winners topic, and a dismissible
  give-and-take composer reminder. No public surface ever shows a low tier or
  a raw score.

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
