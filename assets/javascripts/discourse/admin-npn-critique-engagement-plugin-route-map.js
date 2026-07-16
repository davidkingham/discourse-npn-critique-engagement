export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",

  map() {
    this.route("discourse-npn-critique-engagement-report", { path: "report" });
    this.route("discourse-npn-critique-engagement-health", { path: "health" });
    this.route("discourse-npn-critique-engagement-outreach", {
      path: "outreach",
    });
  },
};
