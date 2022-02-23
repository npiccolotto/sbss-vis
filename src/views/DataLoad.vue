<template>
  <div class="grid">
    <main>
      <MultipleMaps />
    </main>

    <aside>
      <div style="margin-bottom: 10px;">
        Dataset size:
        {{ $store.state.dataset.groups.input.ntiles[0].length }} rows &times;
        {{ $store.state.dataset.groups.input.colnames.length }} columns
      </div>
      <div class="summary-grid">
        <div
          :key="col"
          v-for="col in $store.state.dataset.groups.input.colnames"
        >
          <div style="display:flex;flex-direction:column;">
            <span v-on:click="addVariableToMap('input', col)">{{ col }}</span>
            <VisualSummary group="input" :column="col" />
          </div>
        </div>
      </div>
    </aside>
    <aside class="meta-grid">
      <DensityPlot group="dataset" column="distances" />
      <CorrelationMatrix width="400" height="400" />
      <a href="#/explore">Go further</a>
    </aside>
  </div>
</template>

<script lang="ts">
import VisualSummary from "@/components/SpatialSummary.vue";
import { Component, Vue } from "vue-property-decorator";
import MultipleMaps from "@/components/MultipleMaps.vue";
import CorrelationMatrix from "@/components/CorrelationMatrix/CorrelationMatrix.vue";
import DensityPlot from "@/components/DensityPlot/DensityPlot.vue";

@Component({
  components: {
    VisualSummary,
    MultipleMaps,
    DensityPlot,
    CorrelationMatrix
  },
  computed: {}
})
export default class Home extends Vue {
  addVariableToMap(group: string, column: string) {
    this.$store.dispatch("addVariableToMap", [group, column]);
  }
}
</script>

<style scoped lang="less">
.grid {
  display: grid;
  grid-gap: 10px;
  height: 100vh;
  grid-template-columns: repeat(3, 1fr);
}
.summary-grid {
  display: grid;
  grid-gap: 10px;
  align-content: start;
  grid-template-columns: repeat(4, 64px);
}
.meta-grid {
  display: grid;
  align-content: start;
  grid-template-columns: 1fr;
  grid-gap: 20px;
}
</style>
