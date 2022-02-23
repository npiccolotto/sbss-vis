<template>
  <div class="parameter-container">
    <aside
      style="display:flex; flex-direction:column; justify-content: space-between;"
    >
      <div>
        <h6>
          Density of point distances
          <Hint
            :text="
              'Density plot of pairwise distances between measurement points. Suggests spatial scale of latent components.'
            "
          />
        </h6>
        <DensityPlot
          v-show="$store.state.view.guidanceEnabled"
          group="dataset"
          column="distances"
          :width="300"
        />
      </div>
      <div>
        <h6>
          Empirical Variograms
          <Hint
            :text="
              'The empirical variogram provides a description of how the data are related to distance.'
            "
          />
        </h6>
        <Variograms v-show="$store.state.view.guidanceEnabled" :width="350" />
      </div>
      <ParameterGuidance
        v-show="$store.state.view.guidanceEnabled"
        strategy="equal-area"
      />
      <ParameterGuidance
        v-show="$store.state.view.guidanceEnabled"
        strategy="cov-diff"
      />
    </aside>
    <div class="summaries">
      <h6>
        Variables
        <Hint
          :text="
            'Variables in the dataset. If they are compositional data (parts of a whole, e.g., element concentrations in a soil sample) they were ILR-transformed. Original variables: ' +
              variablesList
          "
        />
      </h6>
      <div class="summary-grid" v-show="$store.state.view.guidanceEnabled">
        <div
          :key="col"
          v-for="col in $store.state.dataset.groups.param.colnames"
        >
          <div style="display:flex;flex-direction:column;">
            <small>{{ col }}</small>
            <VisualSummary group="param" :column="col" />
          </div>
        </div>
      </div>
    </div>
    <main>
      <Map />
    </main>
    <aside>
      <h6>Current Parametrization</h6>
      <div class="container" v-show="$store.state.view.guidanceEnabled">
        <div class="region-points">
          <RegionGuidance
            strategy="user"
            level="0"
            analysisTarget="points"
            :width="100"
          />
        </div>
        <div class="region-cov">
          <RegionGuidance
            strategy="user"
            level="0"
            analysisTarget="diff_cov"
            :width="100"
          />
        </div>

        <div class="kernel">
          <KernelGuidance strategy="user" level="0" :width="400" :height="50" />
        </div>
        <div class="kernel-ev" v-if="false">
          <RegionGuidance
            strategy="user"
            level="0"
            analysis-target="kernel-guidance"
            :kernel="currentKernel"
            :width="100"
          />
        </div>
      </div>
      <div style="margin: 20px 0;">
        <b-button size="lg" variant="primary" @click="applyParametrization"
          >Apply</b-button
        >
      </div>
      <div>
        <h6>History</h6>
        <div
          :key="id"
          v-for="id in Object.keys(pastParametrizations)"
          style="display:flex; margin-bottom: 5px;"
        >
          <RegionGuidance :strategy="id" analysisTarget="points" :width="100" />
          <KernelGuidance :strategy="id" :height="50" :width="300" :level="0" />
          <div
            style="display:flex; align-items:center; justify-content:center;"
          >
            <b-button
              title="Download as .RData"
              size="sm"
              variant="light"
              @click="exportParametrization(id)"
              ><b-icon-download></b-icon-download
            ></b-button>
          </div>
        </div>
      </div>
    </aside>
  </div>
</template>

<script lang="ts">
import { Vue, Component } from "vue-property-decorator";
import Map from "@/components/RegionalizationMap.vue";
import ParameterGuidance from "@/components/ParameterGuidance.vue";
import RegionGuidance from "@/components/RegionGuidance.vue";
import KernelGuidance from "@/components/KernelGuidance.vue";
import Variograms from "@/components/Variograms/Variograms.vue";
import VisualSummary from "@/components/SpatialSummary.vue";
import DensityPlot from "@/components/DensityPlot/DensityPlot.vue";
import Hint from "@/components/Hint.vue";
import { StoreState } from "@/types/store";

@Component({
  components: {
    Map,
    ParameterGuidance,
    DensityPlot,
    VisualSummary,
    Hint,
    RegionGuidance,
    KernelGuidance,
    Variograms
  },
  computed: {
    variablesList: function() {
      return (this.$store
        .state as StoreState).dataset.groups.input.colnames.join(", ");
    },
    currentKernel: function() {
      return this.$store.getters.guidanceFocus("user").kernel;
    },
    pastParametrizations: function() {
      return this.$store.state.results;
    }
  }
})
export default class Parameters extends Vue {
  applyParametrization() {
    this.$store.dispatch("applyParametrization");
  }
  exportParametrization(id: any) {
    this.$store.dispatch("exportParametrization", id);
  }
}
</script>

<style lang="less" scoped>
.parameter-container {
  display: grid;
  grid-template-columns: 1fr 1fr 3fr 1fr;
  grid-gap: 10px;
  height: calc(100vh - 72px);
}
.summaries {
  max-height: calc(100vh - 72px);
  overflow-y: scroll;
}
.summary-grid {
  margin-left: 2px;
  display: grid;
  grid-gap: 5px;
  align-content: start;
  grid-template-columns: repeat(3, 64px);
}

.container {
  display: grid;
  grid-template-columns: 100px 100px 100px 100px;
  grid-template-rows: 75px 75px;
  gap: 5px 5px;
  grid-auto-flow: row;
  grid-template-areas:
    "region-points region-cov empty empty"
    "kernel kernel kernel kernel";
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
