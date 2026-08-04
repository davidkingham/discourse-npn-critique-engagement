import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import NpnAwardButton from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-award-button";
import NpnAwardModal from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-award-modal";

const AWARD_REACTIONS =
  "award-thoughtful|award-critique|award-helped-my-work|trophy";
const AWARD_MENU =
  "award-thoughtful:Thoughtful response|award-critique:Valuable critique|award-helped-my-work:Helped my work";
const ENABLED_REACTIONS =
  "heart|award-thoughtful|award-critique|award-helped-my-work";

// The photographer whose work is being critiqued. Anyone else is a
// passer-by as far as the owner-only awards are concerned. The rendering
// test's current user is built without an id, so tests that care about
// ownership give it one.
const VIEWER_ID = 12;
const OTHER_MEMBER_ID = 777;

function postWith(attrs = {}) {
  return {
    id: 42,
    yours: false,
    topic: { archived: false, user_id: OTHER_MEMBER_ID },
    reactions: [],
    current_user_reaction: null,
    likeAction: { canToggle: true },
    ...attrs,
  };
}

function applyAwardSettings(siteSettings) {
  siteSettings.npn_critique_award_reactions = AWARD_REACTIONS;
  siteSettings.npn_critique_award_menu = AWARD_MENU;
  siteSettings.npn_critique_owner_only_awards = "award-helped-my-work";
  siteSettings.discourse_reactions_enabled_reactions = ENABLED_REACTIONS;
  siteSettings.discourse_reactions_allow_any_emoji = false;
}

module(
  "Integration | Component | NPN Critique Engagement | award button",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      applyAwardSettings(this.siteSettings);
    });

    test("shows the award count, ignoring plain likes", async function (assert) {
      const post = postWith({
        reactions: [
          { id: "heart", count: 9 },
          { id: "award-critique", count: 2 },
          { id: "trophy", count: 1 },
        ],
      });

      await render(<template><NpnAwardButton @post={{post}} /></template>);

      assert.dom(".npn-award-button").exists();
      assert.dom(".npn-award-button__count").hasText("3");
    });

    test("stays plain when the post has no awards", async function (assert) {
      const post = postWith({ reactions: [{ id: "heart", count: 4 }] });

      await render(<template><NpnAwardButton @post={{post}} /></template>);

      assert.dom(".npn-award-button").exists();
      assert.dom(".npn-award-button__count").doesNotExist();
      assert.dom(".npn-award-button.--given").doesNotExist();
    });

    test("marks the button when the viewer already gave an award", async function (assert) {
      const post = postWith({
        reactions: [{ id: "award-thoughtful", count: 1 }],
        current_user_reaction: { id: "award-thoughtful", can_undo: true },
      });

      await render(<template><NpnAwardButton @post={{post}} /></template>);

      assert.dom(".npn-award-button.--given").exists();
    });

    test("a plain like of the viewer's own is not treated as an award", async function (assert) {
      const post = postWith({
        reactions: [{ id: "heart", count: 1 }],
        current_user_reaction: { id: "heart", can_undo: true },
      });

      await render(<template><NpnAwardButton @post={{post}} /></template>);

      assert.dom(".npn-award-button.--given").doesNotExist();
    });

    test("hides on the viewer's own post and on archived topics", function (assert) {
      assert.true(NpnAwardButton.shouldRender({ post: postWith() }));
      assert.false(
        NpnAwardButton.shouldRender({ post: postWith({ yours: true }) })
      );
      assert.false(
        NpnAwardButton.shouldRender({
          post: postWith({ topic: { archived: true } }),
        })
      );
    });
  }
);

module(
  "Integration | Component | NPN Critique Engagement | award modal",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      applyAwardSettings(this.siteSettings);
      this.currentUser.set("id", VIEWER_ID);
      // No app shell in a rendering test, so give the modal somewhere to
      // render rather than silently rendering nothing.
      this.owner.lookup("service:modal").containerElement =
        document.querySelector("#ember-testing");
    });

    test("lists every offerable award with its name", async function (assert) {
      const model = { post: postWith() };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert.dom(".npn-award-modal__award").exists({ count: 2 });
      assert
        .dom("[data-award='award-thoughtful'] .npn-award-modal__label")
        .hasText("Thoughtful response");
      assert
        .dom("[data-award='award-critique'] .npn-award-modal__label")
        .hasText("Valuable critique");
      assert
        .dom("[data-award='award-helped-my-work']")
        .doesNotExist("an owner-only award is hidden from a passer-by");
      // The explanations are what the modal exists for, and they come from
      // the locale file keyed by emoji name. A silent lookup miss would
      // leave the modal a prettier version of the picker it replaced.
      assert
        .dom("[data-award='award-critique'] .npn-award-modal__description")
        .hasText(
          i18n("npn_critique_engagement.awards.descriptions.award-critique")
        );
    });

    test("an award with no explanation shows its name alone", async function (assert) {
      // An award an admin adds has no locale entry, and must render as a
      // plain name rather than a missing-translation string.
      this.siteSettings.npn_critique_award_menu = "award-invented:Invented";
      this.siteSettings.discourse_reactions_allow_any_emoji = true;
      const model = { post: postWith() };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert
        .dom("[data-award='award-invented'] .npn-award-modal__label")
        .hasText("Invented");
      assert
        .dom("[data-award='award-invented'] .npn-award-modal__description")
        .doesNotExist();
    });

    test("offers the owner-only award to the photographer, and says why", async function (assert) {
      const model = {
        post: postWith({
          topic: { archived: false, user_id: VIEWER_ID },
        }),
      };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert.dom(".npn-award-modal__award").exists({ count: 3 });
      assert.dom("[data-award='award-helped-my-work']").exists();
      assert
        .dom("[data-award='award-helped-my-work'] .npn-award-modal__owner-only")
        .exists("the photographer is told why this one is theirs alone");
      assert
        .dom("[data-award='award-critique'] .npn-award-modal__owner-only")
        .doesNotExist();
    });

    test("reads the topic owner from created_by when user_id is absent", async function (assert) {
      const model = {
        post: postWith({
          topic: {
            archived: false,
            details: { created_by: { id: VIEWER_ID } },
          },
        }),
      };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert.dom("[data-award='award-helped-my-work']").exists();
    });

    test("warns that an award replaces an existing reaction", async function (assert) {
      const model = {
        post: postWith({
          current_user_reaction: { id: "heart", can_undo: true },
        }),
      };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert.dom(".npn-award-modal__note").exists();
    });

    test("says nothing about replacement when the viewer has not reacted", async function (assert) {
      const model = { post: postWith() };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert.dom(".npn-award-modal__note").doesNotExist();
    });

    test("locks the awards once the viewer's reaction can no longer be undone", async function (assert) {
      const model = {
        post: postWith({
          current_user_reaction: { id: "award-critique", can_undo: false },
        }),
      };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert.dom(".npn-award-modal__note").exists();
      assert.dom("[data-award='award-critique']").isDisabled();
      assert.dom("[data-award='award-thoughtful']").isDisabled();
    });

    test("marks the award the viewer already gave", async function (assert) {
      const model = {
        post: postWith({
          reactions: [{ id: "award-critique", count: 3 }],
          current_user_reaction: { id: "award-critique", can_undo: true },
        }),
      };
      const closeModal = () => {};

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      assert.dom("[data-award='award-critique']").hasClass("--given");
      assert
        .dom("[data-award='award-critique'] .npn-award-modal__count")
        .hasText("3");
      assert.dom("[data-award='award-thoughtful']").doesNotHaveClass("--given");
    });

    test("giving an award toggles the reaction and syncs the post", async function (assert) {
      const post = postWith();
      let closed = false;
      const model = { post };
      const closeModal = () => (closed = true);

      pretender.put(
        "/discourse-reactions/posts/42/custom-reactions/award-critique/toggle.json",
        () =>
          response({
            reactions: [{ id: "award-critique", type: "emoji", count: 1 }],
            current_user_reaction: {
              id: "award-critique",
              type: "emoji",
              can_undo: true,
            },
            current_user_used_main_reaction: false,
            reaction_users_count: 1,
          })
      );

      await render(
        <template>
          <NpnAwardModal @model={{model}} @closeModal={{closeModal}} />
        </template>
      );

      await click("[data-award='award-critique']");

      assert.true(closed, "the modal closes once the award lands");
      assert.strictEqual(post.current_user_reaction.id, "award-critique");
      assert.strictEqual(post.reaction_users_count, 1);
      assert.deepEqual(post.reactions, [
        { id: "award-critique", type: "emoji", count: 1 },
      ]);
    });
  }
);
