import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dCategoryLink from "discourse/ui-kit/helpers/d-category-link";
import NpnFeedImage from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-image";
import { hasImage } from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/feed-thumbnail";

// Genre tags are lowercase-hyphenated slugs; show them as a sentence-case
// label ("black-and-white" → "Black and white").
function humanizeGenre(genre) {
  const words = genre.replace(/-/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

// The shared card body. Every image lane renders the same metadata under the
// image; only the layout around it changes.
//
// A topic with no image renders no box at all. New-member introductions are
// often text-only, and an empty grey rectangle where a photo should be reads
// as a broken image rather than as "this one has no photo".
//
// A pick card also carries a genre label: at carousel size the row of labels
// is what tells a visitor the breadth of what the community shoots.
const NpnFeedCard = <template>
  <a
    class="npn-feed-card {{unless (hasImage @topic) 'npn-feed-card--textual'}}"
    href={{@topic.lastUnreadUrl}}
  >
    {{#if (hasImage @topic)}}
      <div class="npn-feed-card__frame">
        <NpnFeedImage
          @topic={{@topic}}
          @fixedAspect={{@fixedAspect}}
          @natural={{@natural}}
          @targetWidth={{@targetWidth}}
        />
        {{#if @genre}}
          <span class="npn-feed-card__genre">{{humanizeGenre @genre}}</span>
        {{/if}}
      </div>
    {{/if}}
    <div class="npn-feed-card__meta">
      {{! On a photo card the image is the content and the title is just
      clutter; the alt text keeps it for screen readers. A text-only card
      (a new-member intro with no photo) has nothing else to show, so it
      keeps its title. }}
      {{#unless (hasImage @topic)}}
        <span class="npn-feed-card__title">{{@topic.fancyTitle}}</span>
      {{/unless}}
      <span class="npn-feed-card__byline">
        {{! the poster, not the last replier — these lanes are about whose
        work it is }}
        {{dAvatar @topic.creator imageSize="tiny"}}
        <span class="npn-feed-card__author">{{@topic.creator.username}}</span>
        {{#if @showCategory}}
          {{dCategoryLink @topic.category}}
        {{/if}}
      </span>
    </div>
  </a>
</template>;

export default NpnFeedCard;
