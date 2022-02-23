<template>
  <svg
    class="summary-vis"
    :data-group="group"
    :data-column="column"
    :height="cellSize * levelData[0].length"
    :width="cellSize * levelData[0].length"
    v-on:click="handleSizeChange"
    :style="svgStyle"
  >
    <g v-for="(r, i) in levelData" :key="i">
      <g v-for="(c, j) in r" :key="j">
        <image
          :href="iconPath(i, j)"
          :x="cellSize * i"
          :y="cellSize * j"
          :height="cellSize"
          :width="cellSize"
          :style="style(i, j)"
        />
      </g>
    </g>
  </svg>
</template>

<script lang="ts">
import { SpatialSummaryCellValue, StoreState } from "@/types/store";
import { Vue, Component, Prop } from "vue-property-decorator";
import {
  getIconIndexForPercentile,
  getIconUrlForPercentile
} from "@/util/ntile";

class SpatialSummaryClass extends Vue {
  @Prop({ default: "" }) public group!: string;
  @Prop({ default: "" }) public column!: string;
  public level: number = 0;

  public cellSize!: number;
  public cellArea!: number;
  public cellSizePerLevel: number[] = [16, 16, 16, 16, 16];
  public levelData!: number[][];
  public viewportMask!: (0 | 1)[][];
}

@Component<SpatialSummaryClass>({
  computed: {
    svgStyle: function() {
      if (this.level > 0) {
        return {
          position: "absolute",
          zIndex: 10000 + this.level
        };
      }
    },
    cellSize: function() {
      return this.cellSizePerLevel[this.level];
    },
    cellArea: function() {
      return this.cellSize ** 2;
    },
    viewportMask: function() {
      const mask = this.$store.getters.viewportInSpatialSummary(
        this.level,
        this.$store.state.view.bounds
      );
      if (!mask) {
        return [];
      }
      return mask;
    },
    levelData: function() {
      const state = this.$store.state as StoreState;
      if (state.spatialSummaries?.[this.$props.group]?.[this.column]) {
        return state.spatialSummaries[this.$props.group][this.column][
          this.level
        ];
      }
      return [];
    }
  }
})
export default class SpatialSummary extends SpatialSummaryClass {
  handleSizeChange(e: MouseEvent) {
    if (e.shiftKey) {
      this.level = 0;
    } else {
      this.level += 1;
    }
  }
  sideLength(c: SpatialSummaryCellValue) {
    return Math.sqrt(this.cellArea * (c || 0));
  }
  iconPath(i: number, j: number) {
    return getIconUrlForPercentile(
      getIconIndexForPercentile(this.levelData[i][j], 0)
    );
  }
  border(i: number, j: number) {
    const maskVal = this.viewportMask?.[i]?.[j];
    if (maskVal === 1) {
      return "1px solid red";
    }
    return "0px solid transparent";
  }
  opacity(i: number, j: number) {
    const maskVal = this.viewportMask?.[i]?.[j];
    if (maskVal === 1) {
      return 1;
    }
    return 0.2;
  }
  style(i: number, j: number) {
    const opacity = this.opacity(i, j);
    return {
      opacity
    };
  }
}
</script>

<style lang="less" scoped>
.summary-vis {
  outline: 1px solid black;
  background: white;
  user-select: none;
}
.summary {
  display: flex;
  flex-direction: column;
}
.cell {
  display: inline-block;
  border: 1px solid black;
  overflow: hidden;
}
</style>
