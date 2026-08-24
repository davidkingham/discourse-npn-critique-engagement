import Controller from "@ember/controller";

export default class CritiqueEditorsPicksController extends Controller {
  queryParams = ["tag", "week", "window"];
  tag = null;
  week = null;
  window = null;
}
