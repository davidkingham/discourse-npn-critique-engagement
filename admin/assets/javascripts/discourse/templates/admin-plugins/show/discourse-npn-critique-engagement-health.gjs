import { concat } from "@ember/helper";
import { trustHTML } from "@ember/template";
import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import { i18n } from "discourse-i18n";
import periodMonth from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/period-month";

const TIERS = [
  "excellent",
  "healthy",
  "watch",
  "priority_outreach",
  "low_activity",
  "new_member",
];

function tierSegments(month) {
  return TIERS.map((tier) => ({
    tier,
    count: month.tiers[tier],
    label: i18n(`npn_critique_engagement.tiers.${tier}`),
    style: trustHTML(`flex-grow: ${month.tiers[tier]}`),
  })).filter((segment) => segment.count > 0);
}

export default <template>
  <div class="npn-admin-health">
    <DPageSubheader
      @titleLabel={{i18n "npn_critique_engagement.admin.health.title"}}
      @descriptionLabel={{i18n
        "npn_critique_engagement.admin.health.nav_description"
      }}
    />

    {{#if @controller.model.months.length}}
      <table class="d-table npn-admin-health__table">
        <thead class="d-table__header">
          <tr class="d-table__row">
            <th class="d-table__cell --overview">
              {{i18n "npn_critique_engagement.admin.report.period"}}
            </th>
            <th class="d-table__cell --detail">
              {{i18n "npn_critique_engagement.admin.health.members"}}
            </th>
            <th class="d-table__cell --detail">
              {{i18n "npn_critique_engagement.admin.health.volume"}}
            </th>
            <th class="d-table__cell --detail">
              {{i18n "npn_critique_engagement.admin.health.median_ratio"}}
            </th>
            <th class="d-table__cell --detail npn-admin-health__tiers-header">
              {{i18n "npn_critique_engagement.admin.health.tier_distribution"}}
            </th>
          </tr>
        </thead>
        <tbody class="d-table__body">
          {{#each @controller.model.months as |month|}}
            <tr class="d-table__row">
              <td class="d-table__cell --overview">
                <span class="d-table__overview-name">
                  {{#if month.current}}
                    {{i18n "npn_critique_engagement.admin.health.current"}}
                  {{else}}
                    {{periodMonth month.month}}
                  {{/if}}
                </span>
              </td>
              <td class="d-table__cell --detail">
                <div class="d-table__mobile-label">
                  {{i18n "npn_critique_engagement.admin.health.members"}}
                </div>
                {{month.members}}
              </td>
              <td class="d-table__cell --detail">
                <div class="d-table__mobile-label">
                  {{i18n "npn_critique_engagement.admin.health.volume"}}
                </div>
                {{month.total_weighted_replies}}
              </td>
              <td class="d-table__cell --detail">
                <div class="d-table__mobile-label">
                  {{i18n "npn_critique_engagement.admin.health.median_ratio"}}
                </div>
                {{month.median_ratio}}
              </td>
              <td class="d-table__cell --detail">
                <div class="d-table__mobile-label">
                  {{i18n
                    "npn_critique_engagement.admin.health.tier_distribution"
                  }}
                </div>
                <div class="npn-tier-bar">
                  {{#each (tierSegments month) as |segment|}}
                    <span
                      class="npn-tier-bar__segment --{{segment.tier}}"
                      style={{segment.style}}
                      title="{{segment.label}}: {{segment.count}}"
                    ></span>
                  {{/each}}
                </div>
              </td>
            </tr>
          {{/each}}
        </tbody>
      </table>

      <ul class="npn-admin-health__legend">
        {{#each TIERS as |tier|}}
          <li class="npn-admin-health__legend-item">
            <span class="npn-tier-bar__segment --{{tier}}"></span>
            {{i18n (concat "npn_critique_engagement.tiers." tier)}}
          </li>
        {{/each}}
      </ul>
    {{else}}
      <p class="npn-admin-health__empty">
        {{i18n "npn_critique_engagement.admin.health.empty"}}
      </p>
    {{/if}}
  </div>
</template>
