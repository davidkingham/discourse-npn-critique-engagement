import NpnCritiqueNudgeBanner from "discourse/plugins/discourse-npn-critique-engagement/discourse/components/npn-critique-nudge-banner";

// The /submit flow from discourse-npn-submissions — where photo posts
// actually come from. Every photo-submission type is a give-and-take
// moment; the non-photo types (introductions, help) are not.
const PHOTO_TYPES = ["image", "weekly_challenge", "project"];

function photoSubmission(submissionType) {
  return PHOTO_TYPES.includes(submissionType);
}

export default <template>
  <NpnCritiqueNudgeBanner
    @visible={{photoSubmission @outletArgs.submissionType}}
  />
</template>
