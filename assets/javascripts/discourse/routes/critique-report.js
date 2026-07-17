import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class CritiqueReportRoute extends DiscourseRoute {
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
    return ajax("/admin/plugins/critique-engagement/report");
  }

  titleToken() {
    return i18n("npn_critique_engagement.admin.report.title");
  }
}
