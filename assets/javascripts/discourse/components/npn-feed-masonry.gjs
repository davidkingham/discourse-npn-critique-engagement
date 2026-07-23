import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import TopicList from "discourse/models/topic-list";
import NpnFeedCard from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-card";

// The closing Latest lane: masonry columns so every photo keeps its own
// aspect ratio (the uniform grid looked sloppy across mixed ratios), plus
// infinite scroll so it browses like the old Latest page. The first page
// arrives with the feed; each further page is fetched as the sentinel nears
// the viewport.
export default class NpnFeedMasonry extends Component {
  @service store;

  @tracked topics;
  @tracked loading = false;
  @tracked done = false;

  // The feed delivered page 0, so the next fetch is page 1.
  nextPage = 1;
  observer;

  constructor() {
    super(...arguments);
    this.topics = [...(this.args.lane.topics ?? [])];
  }

  @action
  observe(sentinel) {
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          this.loadMore();
        }
      },
      // Start fetching before the sentinel is actually on screen, so the next
      // page is usually ready by the time the reader reaches it.
      { rootMargin: "800px" }
    );
    this.observer.observe(sentinel);
  }

  @action
  disconnect() {
    this.observer?.disconnect();
  }

  @action
  async loadMore() {
    if (this.loading || this.done) {
      return;
    }

    this.loading = true;
    try {
      const response = await ajax("/critique-engagement/feed/latest.json", {
        data: { page: this.nextPage },
      });
      const more = TopicList.topicsFrom(this.store, response) ?? [];

      if (more.length === 0) {
        this.done = true;
      } else {
        this.topics = [...this.topics, ...more];
        this.nextPage++;
      }
    } catch {
      // Stop rather than hammer a failing endpoint; the lane keeps what it has.
      this.done = true;
    } finally {
      this.loading = false;
    }
  }

  <template>
    <div class="npn-feed-masonry">
      {{#each this.topics as |topic|}}
        <div class="npn-feed-masonry__item">
          <NpnFeedCard
            @topic={{topic}}
            @natural={{true}}
            @targetWidth={{400}}
            @showCategory={{true}}
          />
        </div>
      {{/each}}
    </div>

    {{#unless this.done}}
      <div
        class="npn-feed-masonry__sentinel"
        {{didInsert this.observe}}
        {{willDestroy this.disconnect}}
      ></div>
    {{/unless}}
  </template>
}
