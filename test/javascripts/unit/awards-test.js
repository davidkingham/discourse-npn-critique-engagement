import { module, test } from "qunit";
import {
  awardCount,
  awardMenu,
  awardReactionIds,
  currentAwardId,
  isTopicOwner,
  reactionCount,
} from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/awards";

// Two settings describe awards and confusing them breaks things quietly:
// the menu is what the button offers, the reaction list is what counts.
// These tests pin that split, and pin the rule that an award the reactions
// plugin would reject never reaches the modal.
const SETTINGS = {
  npn_critique_award_reactions: "award-thoughtful|award-critique|star2|trophy",
  npn_critique_award_menu:
    "award-thoughtful:Thoughtful response|award-critique:Valuable critique",
  npn_critique_owner_only_awards: "award-critique",
  discourse_reactions_enabled_reactions:
    "heart|award-thoughtful|award-critique",
  discourse_reactions_allow_any_emoji: false,
};

function settings(overrides = {}) {
  return { ...SETTINGS, ...overrides };
}

module("Unit | NPN Critique Engagement | awards", function () {
  test("the counting list keeps the legacy names", function (assert) {
    assert.deepEqual(awardReactionIds(settings()), [
      "award-thoughtful",
      "award-critique",
      "star2",
      "trophy",
    ]);
  });

  test("the menu offers only what it names, in setting order", function (assert) {
    assert.deepEqual(
      awardMenu(settings()).map((award) => [award.id, award.label]),
      [
        ["award-thoughtful", "Thoughtful response"],
        ["award-critique", "Valuable critique"],
      ]
    );
  });

  test("an owner-only award is flagged, not filtered, so callers can decide", function (assert) {
    const menu = awardMenu(settings());

    assert.false(menu[0].ownerOnly, "award-thoughtful is open to anyone");
    assert.true(menu[1].ownerOnly, "award-critique is listed as owner-only");
  });

  test("the topic owner is read from user_id, then created_by", function (assert) {
    const me = { id: 5 };

    assert.true(isTopicOwner({ topic: { user_id: 5 } }, me));
    assert.false(isTopicOwner({ topic: { user_id: 6 } }, me));
    assert.true(
      isTopicOwner({ topic: { details: { created_by: { id: 5 } } } }, me)
    );
    assert.false(
      isTopicOwner({ topic: { details: { created_by: { id: 6 } } } }, me)
    );
    assert.false(isTopicOwner({ topic: {} }, me), "an unknown owner is nobody");
    assert.false(isTopicOwner({ topic: { user_id: 5 } }, null), "anonymous");
  });

  test("an award that is not an enabled reaction is dropped, not offered", function (assert) {
    const menu = awardMenu(
      settings({
        discourse_reactions_enabled_reactions: "heart|award-critique",
      })
    );

    assert.deepEqual(
      menu.map((award) => award.id),
      ["award-critique"]
    );
  });

  test("any emoji is offerable when the reactions plugin allows it", function (assert) {
    const menu = awardMenu(
      settings({
        discourse_reactions_enabled_reactions: "heart",
        discourse_reactions_allow_any_emoji: true,
      })
    );

    assert.strictEqual(menu.length, 2);
  });

  test("an entry with no label falls back to the emoji name", function (assert) {
    const menu = awardMenu(
      settings({ npn_critique_award_menu: "award-critique" })
    );

    assert.strictEqual(menu[0].label, "award-critique");
  });

  test("counts every award on a post, legacy names included", function (assert) {
    const post = {
      reactions: [
        { id: "heart", count: 7 },
        { id: "award-thoughtful", count: 2 },
        { id: "trophy", count: 1 },
      ],
    };

    assert.strictEqual(awardCount(post, awardReactionIds(settings())), 3);
    assert.strictEqual(reactionCount(post, "award-thoughtful"), 2);
    assert.strictEqual(reactionCount(post, "award-processing"), 0);
  });

  test("a post with no reactions counts zero rather than throwing", function (assert) {
    assert.strictEqual(awardCount({}, awardReactionIds(settings())), 0);
  });

  test("a plain like is not read as an award the viewer gave", function (assert) {
    const ids = awardReactionIds(settings());

    assert.strictEqual(
      currentAwardId({ current_user_reaction: { id: "heart" } }, ids),
      null
    );
    assert.strictEqual(
      currentAwardId({ current_user_reaction: { id: "trophy" } }, ids),
      "trophy"
    );
    assert.strictEqual(currentAwardId({}, ids), null);
  });
});
