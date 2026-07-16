import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class CritiqueHallOfFameRoute extends DiscourseRoute {
  @service router;
  @service siteSettings;

  beforeModel() {
    if (!this.siteSettings.npn_critique_engagement_enabled) {
      this.router.replaceWith("discovery.latest");
    }
  }

  model() {
    return ajax("/critique-engagement/hall-of-fame.json");
  }

  titleToken() {
    return i18n("npn_critique_engagement.hall_of_fame.title");
  }
}
