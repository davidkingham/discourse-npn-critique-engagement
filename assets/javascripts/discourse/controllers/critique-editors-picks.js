import Controller from "@ember/controller";

export default class CritiqueEditorsPicksController extends Controller {
  queryParams = ["tag", "week"];
  tag = null;
  week = null;
}
