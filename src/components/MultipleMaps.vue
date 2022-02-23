<template>
  <div class="single-map">
    <div
      class="multiple-maps"
      :style="{
        'grid-template-columns':
          'repeat(' +
          ($store.state.view.variablesInMap.length >= 2 ? 2 : 1) +
          ', 1fr)'
      }"
      v-if="$store.state.view.variablesInMap.length > 0"
    >
      <div
        :key="group + col"
        class="single-map"
        v-for="[group, col] in $store.state.view.variablesInMap"
      >
        <div v-on:click="removeVariableFromMap(group, col)">
          {{ group }} {{ col }}
        </div>
        <DensityPlot
          :width="densityPlotWidth"
          :height="50"
          :group="group"
          :column="col"
        />
        <CustomMap :group="group" :column="col" />
      </div>
    </div>

    <div class="single-map" v-else>
      <Map />
    </div>
  </div>
</template>

<script lang="ts">
import { Vue, Component } from "vue-property-decorator";
import Map from "@/components/Map.vue";
import CustomMap from "@/components/CustomMap.vue";
import DensityPlot from "@/components/DensityPlot/DensityPlot.vue";
import { vw } from "@/util/util";

@Component({
  components: { Map, CustomMap, DensityPlot },
  computed: {
    densityPlotWidth() {
      return this.$store.state.view.variablesInMap.length > 1
        ? vw(25) - 100
        : vw(50) - 100;
    }
  }
})
export default class MultipleMaps extends Vue {
  removeVariableFromMap(group: string, column: string) {
    this.$store.dispatch("removeVariableFromMap", [group, column]);
  }
}
</script>

<style lang="less" scoped>
.multiple-maps {
  height: 100vh;
  width: 50vw;
  display: grid;
  grid-gap: 5px;
}
.single-map {
  display: flex;
  height: 100%;
  flex-direction: column;
  justify-content: space-between;
}
</style>
