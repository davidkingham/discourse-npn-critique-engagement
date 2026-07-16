import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsShowNpnCritiqueEngagementHealthRoute extends Route {
  model() {
    return ajax("/admin/plugins/critique-engagement/health");
  }
}
