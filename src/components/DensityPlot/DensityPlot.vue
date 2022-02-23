<template>
  <Vega
    :spec="spec"
    :width="width"
    :height="height"
    :datasets="{ density, percentileCutsArea }"
  />
</template>

<script lang="ts">
//import { StoreState } from "@/types/store";
import { Component, Prop, Vue } from "vue-property-decorator";
import Vega from "@/components/Vega.vue";
import spec from "./spec.json";
import { StoreState } from "@/types/store";
import {
  getIconIndexForPercentile,
  getIconUrlForPercentile
} from "@/util/ntile";

@Component({
  components: { Vega },
  computed: {
    spec: function() {
      const title: string =
        this.$props.group === "dataset" && this.$props.column === "distances"
          ? "Point Distances (km)"
          : "";
      const actualSpec: any = {
        ...spec
      };
      actualSpec.layer[0].encoding.x.title = title;
      return actualSpec;
    },
    percentileCutsArea: function() {
      const state = this.$store.state as StoreState;
      if (this.$props.group === "input") {
        const colIndex = this.$store.getters.colIndex(
          this.$props.group,
          this.$props.column
        );
        const ntileBorders: number[] =
          state.dataset.groups[this.$props.group].stats.ntileBorders[colIndex];
        const p = ntileBorders.length;
        return ntileBorders
          .map((b, i) =>
            i < p - 1 ? [ntileBorders[i], ntileBorders[i + 1]] : []
          )
          .filter(b => b.length > 0)
          .map(([start, end], i) => ({
            start,
            end,
            center: start + (end - start) / 2,
            imageUrl: getIconUrlForPercentile(
              getIconIndexForPercentile(i + 1, 0)
            )
          }));
      }
      return [];
    },
    density: function() {
      const state = this.$store.state as StoreState;

      if (
        this.$props.group === "dataset" &&
        this.$props.column === "distances"
      ) {
        return state.dataset.distances.density;
      }
      if (!state.dataset.groups[this.$props.group]) {
        return [];
      }
      if (this.$props.group === "input") {
        return state.dataset.groups[this.$props.group].densities[
          this.$store.getters.colIndex(this.$props.group, this.$props.column)
        ]?.density;
      }
    }
  }
})
export default class DensityPlot extends Vue {
  @Prop()
  public group!: string;
  @Prop()
  public column!: string;

  @Prop()
  public width!: number;
  @Prop()
  public height!: number;
}
</script>
