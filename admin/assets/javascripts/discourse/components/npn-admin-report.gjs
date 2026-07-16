import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { userPath } from "discourse/lib/url";
import { eq } from "discourse/truth-helpers";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import DSelect from "discourse/ui-kit/d-select";
import dBoundAvatarTemplate from "discourse/ui-kit/helpers/d-bound-avatar-template";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import NpnTierBadge from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-tier-badge";
import periodMonth from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/period-month";

const TIERS = [
  "excellent",
  "healthy",
  "watch",
  "priority_outreach",
  "low_activity",
  "new_member",
];

const SORTABLE_COLUMNS = [
  { field: "score", labelKey: "score" },
  { field: "trend", labelKey: "trend" },
  { field: "created_topics", labelKey: "shared" },
  { field: "topics_replied", labelKey: "critiqued" },
  { field: "weighted_replies", labelKey: "weighted" },
  { field: "ratio", labelKey: "ratio" },
];

function tierLabel(tier) {
  return i18n(`npn_critique_engagement.tiers.${tier}`);
}

function trendClass(trend) {
  return `npn-admin-report__trend ${trend >= 0 ? "--up" : "--down"}`;
}

function trendIcon(trend) {
  return trend >= 0 ? "arrow-trend-up" : "arrow-trend-down";
}

export default class NpnAdminReport extends Component {
  @tracked dataOverride = null;
  @tracked tierFilter = null;
  @tracked textFilter = "";
  @tracked sortField = "score";
  @tracked sortAsc = false;
  @tracked loading = false;

  get data() {
    return this.dataOverride ?? this.args.model;
  }

  get rows() {
    let rows = this.data.rows;

    if (this.tierFilter) {
      rows = rows.filter((row) => row.tier === this.tierFilter);
    }

    if (this.textFilter) {
      const query = this.textFilter.toLowerCase();
      rows = rows.filter(
        (row) =>
          row.username.toLowerCase().includes(query) ||
          row.name?.toLowerCase().includes(query)
      );
    }

    const direction = this.sortAsc ? 1 : -1;
    const field = this.sortField;
    return [...rows].sort(
      (a, b) => ((a[field] ?? -Infinity) - (b[field] ?? -Infinity)) * direction
    );
  }

  @action
  setSort(field) {
    if (this.sortField === field) {
      this.sortAsc = !this.sortAsc;
    } else {
      this.sortField = field;
      this.sortAsc = false;
    }
  }

  @action
  updateTextFilter(event) {
    this.textFilter = event.target.value;
  }

  @action
  setTierFilter(tier) {
    this.tierFilter = tier;
  }

  @action
  async changePeriod(period) {
    this.loading = true;
    try {
      this.dataOverride = await ajax(
        "/admin/plugins/critique-engagement/report",
        { data: period ? { period: period.slice(0, 7) } : {} }
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  <template>
    <div class="npn-admin-report">
      <DPageSubheader
        @titleLabel={{i18n "npn_critique_engagement.admin.report.title"}}
        @descriptionLabel={{i18n
          "npn_critique_engagement.admin.report.nav_description"
        }}
      />

      <div class="npn-admin-report__filters">
        <DSelect
          @value={{this.data.period_start}}
          @onChange={{this.changePeriod}}
          @includeNone={{false}}
          class="npn-admin-report__period"
          as |select|
        >
          {{#each this.data.periods as |period|}}
            <select.Option @value={{period}}>
              {{periodMonth period}}
            </select.Option>
          {{/each}}
        </DSelect>

        <DSelect
          @value={{this.tierFilter}}
          @onChange={{this.setTierFilter}}
          class="npn-admin-report__tier-filter"
          as |select|
        >
          {{#each TIERS as |tier|}}
            <select.Option @value={{tier}}>{{tierLabel tier}}</select.Option>
          {{/each}}
        </DSelect>

        <input
          type="text"
          class="npn-admin-report__search"
          placeholder={{i18n
            "npn_critique_engagement.admin.report.search_placeholder"
          }}
          value={{this.textFilter}}
          {{on "input" this.updateTextFilter}}
        />
      </div>

      {{#if this.rows.length}}
        <table class="d-table npn-admin-report__table">
          <thead class="d-table__header">
            <tr class="d-table__row">
              <th class="d-table__cell --overview">
                {{i18n "npn_critique_engagement.admin.report.member"}}
              </th>
              <th class="d-table__cell --detail">
                {{i18n "npn_critique_engagement.admin.report.tier"}}
              </th>
              {{#each SORTABLE_COLUMNS as |column|}}
                <th class="d-table__cell --detail">
                  <button
                    type="button"
                    class="npn-admin-report__sort"
                    {{on "click" (fn this.setSort column.field)}}
                  >
                    {{i18n
                      (concat
                        "npn_critique_engagement.admin.report." column.labelKey
                      )
                    }}
                    {{#if (eq this.sortField column.field)}}
                      {{dIcon (if this.sortAsc "caret-up" "caret-down")}}
                    {{/if}}
                  </button>
                </th>
              {{/each}}
              <th class="d-table__cell --detail">
                {{i18n "npn_critique_engagement.admin.report.finalized"}}
              </th>
            </tr>
          </thead>
          <tbody class="d-table__body">
            {{#each this.rows as |row|}}
              <tr class="d-table__row">
                <td class="d-table__cell --overview">
                  <a
                    class="npn-admin-report__member"
                    href={{userPath row.username}}
                    data-user-card={{row.username}}
                  >
                    {{dBoundAvatarTemplate row.avatar_template "small"}}
                    <span class="d-table__overview-name">{{row.username}}</span>
                  </a>
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.tier"}}
                  </div>
                  <NpnTierBadge @tier={{row.tier}} />
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.score"}}
                  </div>
                  {{row.score}}
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.trend"}}
                  </div>
                  {{#if row.trend}}
                    <span class={{trendClass row.trend}}>
                      {{dIcon (trendIcon row.trend)}}
                      {{row.trend}}
                    </span>
                  {{/if}}
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.shared"}}
                  </div>
                  {{row.created_topics}}
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.critiqued"}}
                  </div>
                  {{row.topics_replied}}
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.weighted"}}
                  </div>
                  {{row.weighted_replies}}
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.ratio"}}
                  </div>
                  {{row.ratio}}
                </td>
                <td class="d-table__cell --detail">
                  <div class="d-table__mobile-label">
                    {{i18n "npn_critique_engagement.admin.report.finalized"}}
                  </div>
                  {{#if row.finalized}}{{dIcon "check"}}{{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      {{else if this.data.rows.length}}
        <p class="npn-admin-report__empty">
          {{i18n "npn_critique_engagement.admin.report.no_results"}}
        </p>
      {{else}}
        <p class="npn-admin-report__empty">
          {{i18n "npn_critique_engagement.admin.report.empty"}}
        </p>
      {{/if}}
    </div>
  </template>
}
