import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { throttle } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import TopicList from "discourse/models/topic-list";
import NpnFeedCard from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-card";
import {
  aspectFor,
  hasImage,
} from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/feed-thumbnail";

// The closing Latest lane: true masonry with infinite scroll, so it browses
// like the old Latest page.
//
// Two deliberate choices, both to keep scrolling smooth:
//   * Items are distributed into columns in JavaScript — each new one goes to
//     the currently shortest column — so appending a page never re-flows the
//     items already on screen. (A CSS `columns` layout rebalances every column
//     on append, which is the jump.)
//   * A scroll listener fetches the next page while a couple of viewports of
//     content still sit below the fold, so it is ready before the reader
//     reaches it — rather than stalling at the very bottom.
const TARGET_COLUMN_WIDTH = 240;
const LOAD_AHEAD_PX = 2000;
// Rough per-item heights (in units of column width) for balancing columns: an
// image is width / aspect tall plus its caption; a text card is short.
const CAPTION_UNITS = 0.4;
const TEXT_UNITS = 0.6;

export default class NpnFeedMasonry extends Component {
  @service store;

  @tracked columns = [];

  loading = false;
  done = false;
  nextPage = 1; // the feed delivered page 0

  heights = [];
  columnCount = 0;
  container;
  onScroll;

  constructor() {
    super(...arguments);
    this.pending = [...(this.args.lane.topics ?? [])];
  }

  @action
  setup(container) {
    this.container = container;
    this.distribute();

    this.onScroll = () => throttle(this, this.maybeLoad, 100);
    window.addEventListener("scroll", this.onScroll, { passive: true });
    window.addEventListener("resize", this.onScroll, { passive: true });
    // A short first screen might already be within the buffer.
    this.maybeLoad();
  }

  @action
  teardown() {
    window.removeEventListener("scroll", this.onScroll);
    window.removeEventListener("resize", this.onScroll);
  }

  columnsForWidth() {
    const width = this.container?.offsetWidth || 0;
    return Math.max(1, Math.floor(width / TARGET_COLUMN_WIDTH) || 1);
  }

  // (Re)build every column from `pending`. Used on first render and on a
  // column-count change from a resize.
  distribute() {
    this.columnCount = this.columnsForWidth();
    this.heights = new Array(this.columnCount).fill(0);
    const columns = Array.from({ length: this.columnCount }, () => []);
    this.pending.forEach((topic) => this.place(topic, columns));
    this.pending = [];
    this.columns = columns;
  }

  place(topic, columns) {
    const units = hasImage(topic)
      ? 1 / aspectFor(topic) + CAPTION_UNITS
      : TEXT_UNITS;

    let shortest = 0;
    for (let i = 1; i < this.heights.length; i++) {
      if (this.heights[i] < this.heights[shortest]) {
        shortest = i;
      }
    }
    columns[shortest].push(topic);
    this.heights[shortest] += units;
  }

  // Append only — existing items keep their column and position.
  append(topics) {
    const columns = this.columns.map((column) => [...column]);
    topics.forEach((topic) => this.place(topic, columns));
    this.columns = columns;
  }

  maybeLoad() {
    // A throttled call can land after teardown; don't touch a dead component.
    if (this.isDestroying || this.isDestroyed) {
      return;
    }
    if (this.loading || this.done || !this.container) {
      return;
    }

    if (this.columnsForWidth() !== this.columnCount) {
      this.pending = this.columns.flat();
      this.distribute();
    }

    const remaining =
      document.documentElement.scrollHeight -
      (window.scrollY + window.innerHeight);
    if (remaining <= LOAD_AHEAD_PX) {
      this.loadMore();
    }
  }

  async loadMore() {
    if (this.loading || this.done || this.isDestroying || this.isDestroyed) {
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
        this.append(more);
        this.nextPage++;
      }
    } catch {
      // Stop rather than hammer a failing endpoint; keep what is loaded.
      this.done = true;
    } finally {
      this.loading = false;
      // A single page may not have filled the buffer (tall screen, fast
      // scroll) — check again so loading keeps up.
      if (!this.done) {
        throttle(this, this.maybeLoad, 100);
      }
    }
  }

  <template>
    <div
      class="npn-feed-masonry"
      {{didInsert this.setup}}
      {{willDestroy this.teardown}}
    >
      {{#each this.columns key="@index" as |column|}}
        <div class="npn-feed-masonry__column">
          {{#each column key="id" as |topic|}}
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
      {{/each}}
    </div>
  </template>
}
