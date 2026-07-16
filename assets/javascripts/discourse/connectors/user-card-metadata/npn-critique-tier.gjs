import { i18n } from "discourse-i18n";
import NpnCritiqueChip from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-critique-chip";
import NpnTierBadge from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-tier-badge";

// Public recognition chip for everyone; tier + score only for staff — a
// member never sees another member's standing.
export default <template>
  {{#if @outletArgs.user.npn_critique_recognition}}
    <div class="npn-critique-user-card__recognition">
      <NpnCritiqueChip @level={{@outletArgs.user.npn_critique_recognition}} />
    </div>
  {{/if}}
  {{#if @outletArgs.user.npn_critique_engagement}}
    <div
      class="npn-critique-user-card"
      title={{i18n "npn_critique_engagement.user_card.label"}}
    >
      <NpnTierBadge @tier={{@outletArgs.user.npn_critique_engagement.tier}} />
      <span class="npn-critique-user-card__score">
        {{@outletArgs.user.npn_critique_engagement.score}}
      </span>
    </div>
  {{/if}}
</template>
