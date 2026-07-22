import Component from "@glimmer/component";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { eq } from "discourse/truth-helpers";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dCategoryLink from "discourse/ui-kit/helpers/d-category-link";
import { i18n } from "discourse-i18n";
import NpnFeedCard from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-card";
import {
  aspectFor,
  clampAspect,
} from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/feed-thumbnail";

// Editors' picks are covers, so a fixed shape is right and cropping is
// acceptable. This is the only place in the feed that crops.
const HERO_ASPECT = 3 / 2;

// One lane, rendered in the layout its job calls for.
//
//   hero       cropped covers, largest — the shop window
//   justified  uniform height, variable width, never cropped, reads left to
//              right so the fairness ranking stays legible. Masonry cannot
//              do that: it is column-major, so it scrambles rank.
//   cards      a small uniform grid
//   rows       text only — a discussion has no photo, and rendering it in a
//              photo grid as an empty box is why discussions get scrolled past
export default class NpnFeedLane extends Component {
  @service siteSettings;

  // Flex-basis and flex-grow both scale with the aspect ratio, so every item
  // in a justified row lands on the same height without measuring anything
  // in JavaScript — and without cropping, which is the whole point.
  itemStyle = (topic) => {
    const aspect = clampAspect(
      aspectFor(topic),
      this.siteSettings.npn_fair_feed_min_aspect,
      this.siteSettings.npn_fair_feed_max_aspect
    );
    const basis = aspect * this.siteSettings.npn_fair_feed_row_height;
    return trustHTML(`flex: ${aspect} 1 ${basis}px;`);
  };

  get heading() {
    return i18n(
      `npn_critique_engagement.feed.lanes.${this.args.lane.name}.title`
    );
  }

  get description() {
    return i18n(
      `npn_critique_engagement.feed.lanes.${this.args.lane.name}.description`
    );
  }

  get heroAspect() {
    return HERO_ASPECT;
  }

  <template>
    <section
      class="npn-feed-lane npn-feed-lane--{{@lane.layout}}"
      data-lane={{@lane.name}}
    >
      <header class="npn-feed-lane__header">
        <h2 class="npn-feed-lane__title">{{this.heading}}</h2>
        <p class="npn-feed-lane__description">{{this.description}}</p>
      </header>

      {{#if (eq @lane.layout "hero")}}
        <div class="npn-feed-lane__hero">
          {{#each @lane.topics as |topic|}}
            <NpnFeedCard
              @topic={{topic}}
              @fixedAspect={{this.heroAspect}}
              @targetWidth={{600}}
            />
          {{/each}}
        </div>

      {{else if (eq @lane.layout "justified")}}
        <div class="npn-feed-lane__justified">
          {{#each @lane.topics as |topic|}}
            <div
              class="npn-feed-lane__justified-item"
              style={{this.itemStyle topic}}
            >
              <NpnFeedCard @topic={{topic}} @targetWidth={{500}} />
            </div>
          {{/each}}
        </div>

      {{else if (eq @lane.layout "cards")}}
        <div class="npn-feed-lane__cards">
          {{#each @lane.topics as |topic|}}
            <NpnFeedCard
              @topic={{topic}}
              @targetWidth={{300}}
              @showCategory={{true}}
            />
          {{/each}}
        </div>

      {{else}}
        <ul class="npn-feed-lane__rows">
          {{#each @lane.topics as |topic|}}
            <li class="npn-feed-row">
              <a class="npn-feed-row__title" href={{topic.lastUnreadUrl}}>
                {{topic.fancyTitle}}
              </a>
              <p class="npn-feed-row__excerpt">{{topic.excerpt}}</p>
              <div class="npn-feed-row__meta">
                {{dCategoryLink topic.category}}
                <span class="npn-feed-row__posters">
                  {{#each topic.posters as |poster|}}
                    {{dAvatar poster.user imageSize="tiny"}}
                  {{/each}}
                </span>
                <span class="npn-feed-row__replies">
                  {{topic.replyCount}}
                </span>
              </div>
            </li>
          {{/each}}
        </ul>
      {{/if}}
    </section>
  </template>
}
