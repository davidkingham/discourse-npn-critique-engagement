import NpnFeedLane from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-feed-lane";

// The composed homepage. Lanes arrive already ordered and already filtered of
// anything empty, so this renders exactly what the server decided to show.
const NpnFairFeed = <template>
  {{#if @outletArgs.model.lanes}}
    <div class="npn-feed">
      {{#each @outletArgs.model.lanes as |lane|}}
        <NpnFeedLane @lane={{lane}} />
      {{/each}}
    </div>
  {{/if}}
</template>;

export default NpnFairFeed;
