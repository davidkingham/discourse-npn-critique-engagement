import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class UserCritiqueImpactRoute extends DiscourseRoute {
  @service currentUser;
  @service router;
  @service siteSettings;

  // The panel is private: only the member themselves ever sees it.
  beforeModel() {
    if (
      !this.siteSettings.npn_critique_engagement_enabled ||
      !this.currentUser ||
      this.currentUser.id !== this.modelFor("user").id
    ) {
      this.router.replaceWith("user.summary", this.modelFor("user"));
    }
  }

  model() {
    return ajax("/critique-engagement/impact.json");
  }
}
