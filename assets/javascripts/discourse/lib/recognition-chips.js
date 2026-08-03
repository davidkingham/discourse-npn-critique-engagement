import { i18n } from "discourse-i18n";

// Shared by the poster-icon initializer (which needs plain strings) and the
// user-card components (which render markup), so the icon, class, and copy for
// a chip are defined once.

const RECOGNITION_ICONS = {
  steward: "trophy",
  guide: "award",
  contributor: "medal",
  rising: "seedling",
};

const RECOGNITION_LABEL_SETTINGS = {
  steward: "npn_critique_pillar_badge_name",
  guide: "npn_critique_supporter_badge_name",
  contributor: "npn_critique_contributor_badge_name",
  rising: "npn_critique_rising_badge_name",
};

export function recognitionIcon(level) {
  return RECOGNITION_ICONS[level] ?? "medal";
}

// Labels come from the badge-name settings so the chip, the badge, and the
// hall of fame always agree.
export function recognitionLabel(siteSettings, level) {
  return siteSettings[
    RECOGNITION_LABEL_SETTINGS[level] ?? "npn_critique_contributor_badge_name"
  ];
}

export function recognitionClass(level) {
  return `npn-critique-chip --${level}`;
}

// Deliberately not "hand-holding-heart": that glyph already means
// priority_outreach on the staff tier badge.
export const GIVEN_CHIP_ICON = "handshake";
export const GIVEN_CHIP_CLASS = "npn-given-chip";

// The serialized count is a band floor, so it always reads as "N+".
export function givenChipText(count) {
  return `${count}+`;
}

export function givenChipLabel(siteSettings, count) {
  return i18n("npn_critique_engagement.given_chip.label", {
    count,
    days: siteSettings.npn_critique_window_days,
  });
}
