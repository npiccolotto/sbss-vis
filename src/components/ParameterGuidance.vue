<template>
  <div>
    <h6>
      {{ strategyLabel }}
      <Hint :text="strategyHint" />
    </h6>
    <div class="thumbnail-grid">
      <div
        v-for="(region, level) in regions"
        :key="level"
        style="cursor: pointer;"
        @click="setGuidanceFocus(level)"
      >
        <small
          :style="{
            'text-align': 'center',
            display: 'inline-block',
            width: '100%',
            'font-weight':
              currentRegionalizationLevel === level ? 'bold' : 'normal'
          }"
          >{{
            strategy === "equal-area"
              ? level + 1 + "x" + (level + 1)
              : level + 1
          }}</small
        >
        <RegionGuidance
          analysis-target="points"
          :strategy="strategy"
          :level="level"
          :width="40"
          :with-legend="false"
        />
      </div>
    </div>
    <div class="container">
      <div class="region-points">
        <RegionGuidance
          :strategy="strategy"
          :level="currentRegionalizationLevel"
          analysis-target="points"
          :width="100"
        />
      </div>
      <div class="region-cov">
        <RegionGuidance
          :strategy="strategy"
          :level="currentRegionalizationLevel"
          analysis-target="diff_cov"
          :width="100"
        />
      </div>
      <div class="kernel">
        <KernelGuidance
          :strategy="strategy"
          :level="currentRegionalizationLevel"
          :width="300"
          :height="50"
        />
      </div>
      <div class="kernel-ev" v-if="false">
        <RegionGuidance
          :strategy="strategy"
          :level="currentRegionalizationLevel"
          analysis-target="kernel-guidance"
          :kernel="currentKernel"
          :width="75"
        />
      </div>
    </div>
  </div>
</template>

<script lang="ts">
import { Vue, Component, Prop } from "vue-property-decorator";
import RegionGuidance from "@/components/RegionGuidance.vue";
import KernelGuidance from "@/components/KernelGuidance.vue";
import { StoreState } from "@/types/store";
import Hint from "@/components/Hint.vue";

class ParameterGuidanceClass extends Vue {
  @Prop({ default: "equal-area" }) public strategy!: string;
}

@Component<ParameterGuidanceClass>({
  components: { RegionGuidance, KernelGuidance, Hint },
  computed: {
    strategyLabel: function() {
      if (this.strategy === "equal-area") {
        return "Precomputed grid partition";
      }
      if (this.strategy === "cov-diff") {
        return "Precomputed covariance-based partition";
      }
      return this.strategy;
    },
    strategyHint: function() {
      if (this.strategy === "equal-area") {
        return "A partition where the bounding box is divided into N x N parts. All parts have the same area.";
      }
      if (this.strategy === "cov-diff") {
        return "A partition where boundaries are drawn such that similar covariances are grouped. Parts have different areas.";
      }
      return this.strategy;
    },
    currentKernel: function() {
      return this.$store.getters.guidanceFocus(this.strategy).kernel;
    },
    currentRegionalizationLevel: function() {
      return (this.$store.state as StoreState).view.parameterInput.focus[
        this.strategy
      ]?.regionalizationLevel;
    },
    regions: function() {
      return this.$store.state.guidance[this.strategy].regions;
    }
  }
})
export default class ParameterGuidance extends ParameterGuidanceClass {
  setGuidanceFocus(level: number) {
    this.$store.dispatch("setParameterInputFocus", {
      focus: { regionalizationLevel: level },
      strategy: this.strategy
    });
  }
}
</script>

<style lang="less" scoped>
.thumbnail-grid {
  display: grid;
  grid-template-columns: repeat(8, 40px);
  grid-gap: 5px;
  margin-bottom: 5px;
}
.container {
  display: grid;
  grid-template-columns: 100px 100px 100px;
  grid-template-rows: 1fr 1fr;
  gap: 5px 5px;
  grid-auto-flow: row;
  grid-template-areas:
    "region-points region-cov empty"
    "kernel kernel kernel";
}
.kernel {
  grid-area: kernel;
}
.empty {
  grid-area: empty;
}
.kernel-ev {
  grid-area: kernel-ev;
}
.region-points {
  grid-area: region-points;
}
.region-cov {
  grid-area: region-cov;
}
.revion-ev {
  grid-area: revion-ev;
}
</style>
