import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class CritiqueModerateRoute extends DiscourseRoute {
  @service currentUser;
  @service router;
  @service siteSettings;

  beforeModel() {
    if (
      !this.siteSettings.npn_critique_engagement_enabled ||
      !this.currentUser?.staff
    ) {
      this.router.replaceWith("discovery.latest");
    }
  }

  model() {
    return ajax("/critique-engagement/moderate.json");
  }

  titleToken() {
    return i18n("npn_critique_engagement.moderate.title");
  }
}
