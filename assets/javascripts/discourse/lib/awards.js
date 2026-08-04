import I18n, { i18n } from "discourse-i18n";

// Awards are ordinary discourse-reactions reactions that this plugin treats
// as honors: they carry more weight in the scorer, they decide the hall of
// fame, and they earn post-tied badges. Two settings describe them and they
// are not interchangeable:
//
//   npn_critique_award_reactions — every emoji that *counts* as an award,
//     including the legacy names used before the custom rosettes existed.
//     Use this to read award state off a post.
//   npn_critique_award_menu — the awards the button *offers*, in display
//     order, with their labels. Never includes the legacy names.

function settingList(value) {
  return (value || "").split("|").filter(Boolean);
}

// Every emoji that counts as an award, for reading state off a post.
export function awardReactionIds(siteSettings) {
  return settingList(siteSettings.npn_critique_award_reactions);
}

// The awards the button offers: [{ id, label, description, ownerOnly }, ...]
// in setting order. Anything the reactions plugin would reject is dropped
// here rather than offered and failed on click. Owner-only awards are
// flagged rather than filtered, because whether to show them depends on who
// is looking — see `isTopicOwner`.
export function awardMenu(siteSettings) {
  const anyEmojiAllowed = siteSettings.discourse_reactions_allow_any_emoji;
  const enabled = new Set(
    settingList(siteSettings.discourse_reactions_enabled_reactions)
  );
  const ownerOnly = new Set(
    settingList(siteSettings.npn_critique_owner_only_awards)
  );

  return settingList(siteSettings.npn_critique_award_menu)
    .map((entry) => {
      // Only the first colon separates emoji from label, so a label may
      // contain one.
      const separator = entry.indexOf(":");
      const id = (separator === -1 ? entry : entry.slice(0, separator)).trim();
      const label =
        separator === -1 ? "" : entry.slice(separator + 1).trim() || id;

      return {
        id,
        label: label || id,
        description: awardDescription(id),
        ownerOnly: ownerOnly.has(id),
      };
    })
    .filter((award) => award.id && (anyEmojiAllowed || enabled.has(award.id)));
}

// Whether the viewer is the photographer whose work is being critiqued.
// TopicViewSerializer carries the topic author as `user_id`; `created_by`
// covers the paths where only the topic details are loaded.
export function isTopicOwner(post, currentUser) {
  if (!currentUser || !post?.topic) {
    return false;
  }
  const ownerId = post.topic.user_id ?? post.topic.details?.created_by?.id;
  return !!ownerId && ownerId === currentUser.id;
}

// The one-line explanation shown under an award's name. Translations exist
// for the awards this plugin ships; an award an admin adds simply shows its
// label alone rather than a missing-translation string.
function awardDescription(id) {
  const key = `npn_critique_engagement.awards.descriptions.${id}`;
  return I18n.lookup(key) === undefined ? null : i18n(key);
}

// How many awards a post has received, across every counting emoji.
export function awardCount(post, awardIds) {
  const ids = new Set(awardIds);
  return (post?.reactions || []).reduce(
    (total, reaction) =>
      ids.has(reaction.id) ? total + reaction.count : total,
    0
  );
}

// How many times one specific award was given on a post.
export function reactionCount(post, reactionId) {
  return (
    (post?.reactions || []).find((reaction) => reaction.id === reactionId)
      ?.count || 0
  );
}

// The award the viewer has already given on this post, if any. Reactions
// allow one per member per post, so there is at most one.
export function currentAwardId(post, awardIds) {
  const given = post?.current_user_reaction?.id;
  return given && awardIds.includes(given) ? given : null;
}
