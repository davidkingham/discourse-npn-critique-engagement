import { eq } from "discourse/truth-helpers";
import NpnCritiqueNudgeBanner from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-critique-nudge-banner";

// The /submit flow from discourse-npn-submissions — where image critique
// posts actually come from. "image" is the critique-category submission;
// other types (weekly challenge, introductions, …) don't carry the
// give-and-take expectation.
export default <template>
  <NpnCritiqueNudgeBanner @visible={{eq @outletArgs.submissionType "image"}} />
</template>
