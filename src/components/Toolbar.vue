<template>
  <div class="global-controls">
    <!--
    <div>
      <label for="toolbar-locationdensity" style="display:block;"
        ><small
          >Location density: {{ $store.state.view.locationDensity }}</small
        ></label
      >
      <b-form-input
        size="sm"
        id="toolbar-locationdensity"
        type="range"
        :min="0"
        :max="1"
        :step="0.1"
        v-model.number="locationDensity"
      />
    </div>-->
    <div>
      <input
        id="toolbar-guidance"
        type="checkbox"
        :checked="$store.state.view.guidanceEnabled"
        @change="toggleGuidanceEnabled"
      />
      <label for="toolbar-guidance">Guidance enabled</label>
    </div>
    <div>
      <b-button size="sm" @click="resetViewport">
        Reset viewport
      </b-button>
    </div>
    <div>
      <div>
        <label for="toolbar-numpoints" style="display:block;"
          ><small
            >Min # points (out of {{ $store.state.dataset.locations.length }}):
          </small></label
        >
        <input
          id="toolbar-numpoints"
          :disabled="!$store.state.view.guidanceEnabled"
          class="form-control form-control-sm"
          v-model.number="$store.state.view.parameterInput.minNumPoints"
          :state="
            $store.state.view.parameterInput.minNumPoints >= 0 &&
              $store.state.view.parameterInput.minNumPoints <
                $store.state.dataset.locations.length
          "
          type="number"
        />
      </div>
    </div>
    <div></div>
    <div>
      <span>Legend</span>
    </div>
    <div v-show="$store.state.view.guidanceEnabled">
      <ColorLegendHorizontal width="150" color="Oranges" />
      <small
        >Number of Points
        <Hint
          :text="
            'The orange color scale shows how many points a region or kernel contains. Darker is more points.'
          "
      /></small>
    </div>
    <div v-show="$store.state.view.guidanceEnabled">
      <ColorLegendHorizontal width="150" color="Greens" />
      <small
        >Region Specialness
        <Hint
          :text="
            'The green color scale shows how the sample covariance in a partition differs from the global sample covariance. Darker means more difference, i.e., more special.'
          "
      /></small>
    </div>
    <div v-show="false">
      <ColorLegendHorizontal width="150" color="Blues" />
      <small
        >Eigenvalue Difference
        <Hint
          :text="
            'The blue color scale shows an SBSS-theory-based measure to indicate good parameters, which unfortunately requires knowledge of the a-priori unknown latent components. We use the input data for the same computations, in the hope that the outcome may still be helpful. Darker is better.'
          "
      /></small>
    </div>
    <div>
      <div>
        <img
          src="images/icons_1.png"
          class="toolbar-icon"
          title="1st sextile (0-16.67% of data)"
          alt=""
        />
        <img
          src="images/icons_2.png"
          class="toolbar-icon"
          title="2nd sextile (16.67-33.34% of data)"
          alt=""
        />
        <img
          src="images/icons_3.png"
          class="toolbar-icon"
          title="3rd sextile (33.34-50% of data)"
          alt=""
        />
        <img
          src="images/icons_4.png"
          class="toolbar-icon"
          title="4th sextile (50-66.67% of data)"
          alt=""
        />
        <img
          src="images/icons_5.png"
          class="toolbar-icon"
          title="5th sextile (66.67-83.35% of data)"
          alt=""
        />
        <img
          src="images/icons_6.png"
          class="toolbar-icon"
          title="6th sextile (83.35-100% of data)"
          alt=""
        />
      </div>
      <small>Lower to upper sextile (16.67% of data)</small>
    </div>
    <!-- <div>
      <a href="#/new">New params</a>
    </div> -->
  </div>
</template>

<script lang="ts">
import { Vue, Component } from "vue-property-decorator";
import ColorLegendHorizontal from "@/components/ColorLegendHorizontal.vue";
import Hint from "@/components/Hint.vue";

@Component({
  components: { ColorLegendHorizontal, Hint },
  watch: {
    locationDensity: function(n, o) {
      if (n !== o) {
        this.$store.dispatch("setLocationDensity", n);
      }
    }
  }
})
export default class Toolbar extends Vue {
  public locationDensity = 0.1;
  resetViewport() {
    this.$store.dispatch("resetViewport");
  }
  toggleGuidanceEnabled() {
    this.$store.state.view.guidanceEnabled = !this.$store.state.view
      .guidanceEnabled;
  }
}
</script>

<style lang="less" scoped>
.global-controls {
  border-bottom: 1px solid lightgray;
  margin-bottom: 10px;
  display: grid;
  grid-template-columns: repeat(3, max-content) 1fr repeat(5, max-content);
  grid-gap: 15px;
  align-items: center;
}
.toolbar-icon {
  width: 16px;
}
</style>
