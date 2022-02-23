<template>
  <Vega :signals="['inputVarsInMap']" :spec="spec" :datasets="correlations" />
</template>

<script lang="ts">
import { StoreState } from "@/types/store";
import { melt } from "@/util/matrix";
import { Component, Vue } from "vue-property-decorator";
import Vega from "@/components/Vega.vue";
import spec from "./spec.json";

@Component({
  components: { Vega },
  computed: {
    correlations: function() {
      const state = this.$store.state as StoreState;
      const molten = melt<number>(
        state.dataset.groups["input"].correlations,
        state.dataset.groups["input"].colnames,
        state.dataset.groups["input"].colnames
      );
      return { correlations: molten };
    },
    spec: function() {
      return spec;
    }
  }
})
export default class CorrelationMatrix extends Vue {}
</script>
