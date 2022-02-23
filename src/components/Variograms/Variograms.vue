<template>
  <Vega
    :spec="spec"
    :width="width"
    :height="height"
    :datasets="{ variogs, diffPerBin, userKernels }"
  />
</template>

<script lang="ts">
import { Component, Prop, Vue } from "vue-property-decorator";
import Vega from "@/components/Vega.vue";
import spec from "./spec.json";
import { StoreState, VariogramValue } from "@/types/store";
import groupBy from "lodash/groupBy";
import * as math from "mathjs";

class DensityPlotClass extends Vue {
  public variogs!: VariogramValue[];

  @Prop({ default: "param" })
  public group!: string;

  @Prop()
  public width!: number;
  @Prop({ default: 70 })
  public height!: number;
}

@Component<DensityPlotClass>({
  components: { Vega },
  computed: {
    spec: function() {
      const actualSpec: any = {
        ...spec
      };
      return actualSpec;
    },

    userKernels: function() {
      const usrK = this.$store.getters.userKernels();
      return usrK;
    },

    diffPerBin: function() {
      type Diff = { value: number; center: number };
      let diffPerBin: Diff[] = [];
      const grouped = groupBy<VariogramValue>(this.variogs, "center");
      for (const [, v] of Object.entries(grouped)) {
        diffPerBin.push({
          value: math.std(v.map(vg => vg.value)),
          center: v[0].center
        });
      }
      return diffPerBin;
    },

    variogs: function() {
      const state = this.$store.state as StoreState;
      return state.dataset.groups[this.$props.group].variogs;
    }
  }
})
export default class DensityPlot extends DensityPlotClass {}
</script>
