import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";
import TopicList from "discourse/models/topic-list";

// Wires the fair feed into core: "Fair" as a category sort option, and the
// custom homepage's model. The server decides whether "/" is ours at all
// (the :custom_homepage_enabled modifier); this only supplies the data once
// core has routed there.
export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");
  if (!siteSettings.npn_critique_engagement_enabled) {
    return;
  }

  // Puts "Fair" in the category settings sort dropdown, so Image Critiques
  // can default to the equity ordering without anyone touching a URL.
  api.addCategorySortCriteria("fair");

  if (!siteSettings.npn_fair_feed_enabled) {
    return;
  }

  const store = api.container.lookup("service:store");

  api.registerBehaviorTransformer("custom-homepage-model", async () => {
    const response = await ajax("/critique-engagement/feed.json");

    return {
      lanes: response.lanes.map((lane) => ({
        name: lane.name,
        layout: lane.layout,
        // Each lane carries its own users/primary_groups sideloads, which is
        // where topicsFrom looks for them.
        topics: TopicList.topicsFrom(store, lane),
      })),
    };
  });
});
