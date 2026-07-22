import Component from "@glimmer/component";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import {
  aspectFor,
  clampAspect,
  thumbnailFor,
} from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/feed-thumbnail";

// One image in a feed lane, in a box whose shape is known before the image
// loads — so nothing shifts as the page fills in.
//
// Outside the hero lane the fit is always `contain`. When the box matches the
// image's aspect exactly that is indistinguishable from `cover`; when the
// aspect had to be clamped (a panorama, a tall portrait) it letterboxes
// instead of cropping. NPN never crops a member's work.
export default class NpnFeedImage extends Component {
  @service siteSettings;

  get aspect() {
    const actual = aspectFor(this.args.topic);

    if (this.args.fixedAspect) {
      return this.args.fixedAspect;
    }

    return clampAspect(
      actual,
      this.siteSettings.npn_fair_feed_min_aspect,
      this.siteSettings.npn_fair_feed_max_aspect
    );
  }

  get thumbnail() {
    return thumbnailFor(this.args.topic, this.args.targetWidth ?? 400);
  }

  get style() {
    return trustHTML(`aspect-ratio: ${this.aspect};`);
  }

  <template>
    <div
      class="npn-feed-image
        {{if
          @fixedAspect
          'npn-feed-image--cropped'
          'npn-feed-image--contained'
        }}"
      style={{this.style}}
    >
      {{#if this.thumbnail}}
        <img
          src={{this.thumbnail.url}}
          width={{this.thumbnail.width}}
          height={{this.thumbnail.height}}
          alt={{@topic.fancyTitle}}
          loading="lazy"
          decoding="async"
        />
      {{/if}}
    </div>
  </template>
}
