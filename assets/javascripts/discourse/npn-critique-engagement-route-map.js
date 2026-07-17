export default function () {
  this.route("critique-leaderboard", {
    path: "/critique-engagement/leaderboard",
  });
  this.route("critique-hall-of-fame", {
    path: "/critique-engagement/hall-of-fame",
  });
  this.route("critique-moderate", { path: "/moderate" });
  this.route("critique-editors-picks", { path: "/moderate/editors-picks" });
  this.route("critique-outreach", { path: "/moderate/outreach" });
  this.route("critique-report", { path: "/moderate/report" });
}
