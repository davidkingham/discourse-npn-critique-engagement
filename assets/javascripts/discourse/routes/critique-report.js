import { service } from "@ember/service";
import { hash } from "rsvp";
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
    return hash({
      report: ajax("/admin/plugins/critique-engagement/report"),
      // The reach series shares the page but its own endpoint; a failure
      // here shouldn't blank the roster, so it degrades to no reach section.
      health: ajax("/admin/plugins/critique-engagement/health").catch(
        () => ({})
      ),
    });
  }

  titleToken() {
    return i18n("npn_critique_engagement.admin.report.title");
  }
}
