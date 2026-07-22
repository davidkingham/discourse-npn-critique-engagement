import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dCategoryLink from "discourse/ui-kit/helpers/d-category-link";
import NpnFeedImage from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-image";

// The shared card body. Every image lane renders the same metadata under the
// image; only the layout around it changes.
const NpnFeedCard = <template>
  <a class="npn-feed-card" href={{@topic.lastUnreadUrl}}>
    <NpnFeedImage
      @topic={{@topic}}
      @fixedAspect={{@fixedAspect}}
      @targetWidth={{@targetWidth}}
    />
    <div class="npn-feed-card__meta">
      <span class="npn-feed-card__title">{{@topic.fancyTitle}}</span>
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
