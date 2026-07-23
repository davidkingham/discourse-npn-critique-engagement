import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { throttle } from "@ember/runloop";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import NpnFeedCard from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-card";

// Editors' picks are covers, so a fixed shape is right and cropping is
// acceptable. This is the only place in the feed that crops.
const HERO_ASPECT = 3 / 2;

// The editors' picks carousel: one pick per genre in a horizontally scrolling
// row. Its scrollability is signalled subtly — a soft fade at each edge that
// has more beyond it, plus arrow buttons that appear on hover — rather than a
// scrollbar. The fades and arrows for an edge only show when there is actually
// something to scroll to in that direction.
export default class NpnFeedCarousel extends Component {
  @tracked atStart = true;
  @tracked atEnd = true;

  heroAspect = HERO_ASPECT;
  track;
  onScroll;

  @action
  setup(track) {
    this.track = track;
    this.update();
    this.onScroll = () => throttle(this, this.update, 50);
    track.addEventListener("scroll", this.onScroll, { passive: true });
    window.addEventListener("resize", this.onScroll, { passive: true });
  }

  @action
  teardown() {
    this.track?.removeEventListener("scroll", this.onScroll);
    window.removeEventListener("resize", this.onScroll);
  }

  update() {
    const track = this.track;
    if (!track) {
      return;
    }
    this.atStart = track.scrollLeft <= 1;
    this.atEnd = track.scrollLeft + track.clientWidth >= track.scrollWidth - 1;
  }

  @action
  scrollByPage(direction) {
    // Not a full page: leave a card of overlap so the eye keeps its place.
    const amount = this.track.clientWidth * 0.8;
    this.track.scrollBy({ left: direction * amount, behavior: "smooth" });
  }

  <template>
    <div class="npn-feed-carousel">
      <button
        type="button"
        class="npn-feed-carousel__arrow --left"
        hidden={{this.atStart}}
        {{on "click" (fn this.scrollByPage -1)}}
      >
        {{dIcon "chevron-left"}}
      </button>

      <div class="npn-feed-carousel__fade --left" hidden={{this.atStart}}></div>

      <div
        class="npn-feed-carousel__track"
        {{didInsert this.setup}}
        {{willDestroy this.teardown}}
      >
        {{#each @topics as |topic|}}
          <div class="npn-feed-carousel__item">
            <NpnFeedCard
              @topic={{topic}}
              @genre={{topic.npn_pick_genre_label}}
              @fixedAspect={{this.heroAspect}}
              @targetWidth={{400}}
            />
          </div>
        {{/each}}
      </div>

      <div class="npn-feed-carousel__fade --right" hidden={{this.atEnd}}></div>

      <button
        type="button"
        class="npn-feed-carousel__arrow --right"
        hidden={{this.atEnd}}
        {{on "click" (fn this.scrollByPage 1)}}
      >
        {{dIcon "chevron-right"}}
      </button>
    </div>
  </template>
}
