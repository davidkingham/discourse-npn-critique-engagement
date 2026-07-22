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
// aspect had to be clamped (a panorama, a tall portrait) the leftover space
// is filled with a blurred, scaled copy of the same photo rather than a flat
// bar — the treatment the topic-thumbnails theme component uses. NPN never
// crops a member's work, and the blur keeps a clamped frame from reading as
// letterboxed dead space.
export default class NpnFeedImage extends Component {
  @service siteSettings;

  get actualAspect() {
    return aspectFor(this.args.topic);
  }

  get aspect() {
    if (this.args.fixedAspect) {
      return this.args.fixedAspect;
    }

    return clampAspect(
      this.actualAspect,
      this.siteSettings.npn_fair_feed_min_aspect,
      this.siteSettings.npn_fair_feed_max_aspect
    );
  }

  // The box was clamped away from the photo's true shape, so `contain` will
  // leave bars. Only then do we need the blurred fill behind it.
  get needsFill() {
    return (
      !this.args.fixedAspect && Math.abs(this.actualAspect - this.aspect) > 0.01
    );
  }

  get thumbnail() {
    return thumbnailFor(this.args.topic, this.args.targetWidth ?? 400);
  }

  get boxStyle() {
    return trustHTML(`aspect-ratio: ${this.aspect};`);
  }

  get fillStyle() {
    return trustHTML(`background-image: url(${this.thumbnail.url});`);
  }

  <template>
    <div
      class="npn-feed-image
        {{if
          @fixedAspect
          'npn-feed-image--cropped'
          'npn-feed-image--contained'
        }}"
      style={{this.boxStyle}}
    >
      {{#if this.thumbnail}}
        {{#if this.needsFill}}
          <div
            class="npn-feed-image__fill"
            style={{this.fillStyle}}
            aria-hidden="true"
          ></div>
        {{/if}}
        <img
          class="npn-feed-image__img"
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
