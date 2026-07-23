import Component from "@glimmer/component";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { emojiUnescape } from "discourse/lib/text";
import { eq } from "discourse/truth-helpers";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dCategoryLink from "discourse/ui-kit/helpers/d-category-link";
import dDirSpan from "discourse/ui-kit/helpers/d-dir-span";
import { i18n } from "discourse-i18n";
import NpnFeedCard from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-card";
import NpnFeedCarousel from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-carousel";
import NpnFeedMasonry from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-masonry";
import {
  aspectFor,
  clampAspect,
} from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/feed-thumbnail";

// One lane, rendered in the layout its job calls for.
//
//   carousel   editors' picks, one per genre, in a horizontally scrolling row
//   justified  uniform height, variable width, never cropped, reads left to
//              right so the fairness ranking stays legible. Masonry cannot
//              do that: it is column-major, so it scrambles rank.
//   cards      a small uniform grid
//   rows       text only — a discussion has no photo, and rendering it in a
//              photo grid as an empty box is why discussions get scrolled past
//   masonry    the Latest lane — columns at natural aspect, infinite scroll
export default class NpnFeedLane extends Component {
  @service siteSettings;

  // Flex-basis and flex-grow both scale with the aspect ratio, so every item
  // in a justified row lands on the same height without measuring anything
  // in JavaScript — and without cropping, which is the whole point.
  //
  // max-width is what keeps an under-full row honest: flex-grow would
  // otherwise stretch two items across the whole container and tower over
  // the full rows above them. Capped, the leftover width just stays empty.
  itemStyle = (topic) => {
    const aspect = clampAspect(
      aspectFor(topic),
      this.siteSettings.npn_fair_feed_min_aspect,
      this.siteSettings.npn_fair_feed_max_aspect
    );
    const basis = aspect * this.siteSettings.npn_fair_feed_row_height;
    const cap = aspect * this.siteSettings.npn_fair_feed_max_row_height;
    return trustHTML(`flex: ${aspect} 1 ${basis}px; max-width: ${cap}px;`);
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

  <template>
    <section
      class="npn-feed-lane npn-feed-lane--{{@lane.layout}}"
      data-lane={{@lane.name}}
    >
      <header class="npn-feed-lane__header">
        <h2 class="npn-feed-lane__title">{{this.heading}}</h2>
        <p class="npn-feed-lane__description">{{this.description}}</p>
      </header>

      {{#if (eq @lane.layout "carousel")}}
        <NpnFeedCarousel @topics={{@lane.topics}} />

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

      {{else if (eq @lane.layout "masonry")}}
        <NpnFeedMasonry @lane={{@lane}} />

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
              {{#if topic.npn_excerpt}}
                {{! rendered as HTML exactly as core's TopicExcerpt does:
                topics.excerpt is server-generated from sanitized cooked
                HTML, and contains entities that would otherwise show
                literally }}
                <p class="npn-feed-row__excerpt">
                  {{dDirSpan (emojiUnescape topic.npn_excerpt) htmlSafe="true"}}
                </p>
              {{/if}}
              <div class="npn-feed-row__meta">
                {{dCategoryLink topic.category}}
                <span class="npn-feed-row__posters">
                  {{#each topic.posters as |poster|}}
                    {{dAvatar poster.user imageSize="tiny"}}
                  {{/each}}
                </span>
                {{! a bare "0" reads as broken; no replies yet is the
                interesting state, so say it }}
                <span class="npn-feed-row__replies">
                  {{#if topic.replyCount}}
                    {{i18n
                      "npn_critique_engagement.feed.replies"
                      count=topic.replyCount
                    }}
                  {{else}}
                    {{i18n "npn_critique_engagement.feed.no_replies"}}
                  {{/if}}
                </span>
              </div>
            </li>
          {{/each}}
        </ul>
      {{/if}}
    </section>
  </template>
}
