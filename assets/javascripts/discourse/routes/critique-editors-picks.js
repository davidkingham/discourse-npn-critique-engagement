import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class CritiqueEditorsPicksRoute extends DiscourseRoute {
  @service currentUser;
  @service router;
  @service siteSettings;

  queryParams = {
    tag: { refreshModel: true },
  };

  beforeModel() {
    if (
      !this.siteSettings.npn_critique_engagement_enabled ||
      !this.currentUser?.staff
    ) {
      this.router.replaceWith("discovery.latest");
    }
  }

  model(params) {
    return ajax("/moderate/editors-picks.json", {
      data: params.tag ? { tag: params.tag } : {},
    });
  }

  titleToken() {
    return i18n("npn_critique_engagement.editors_picks.title");
  }
}
