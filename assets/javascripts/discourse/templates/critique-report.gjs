import NpnCritiqueReport from "../components/npn-critique-report";

export default <template>
  <NpnCritiqueReport
    @model={{@controller.model.report}}
    @reach={{@controller.model.health.reach}}
  />
</template>
