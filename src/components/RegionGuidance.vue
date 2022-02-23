<template>
  <div
    :style="{
      display: 'grid',
      'grid-template-columns': withLegend
        ? width - legendWidth + 'px ' + legendWidth + 'px'
        : width + 'px ',
      'grid-gap': '5px',
      'align-items': 'center'
    }"
  >
    <svg
      :width="withLegend ? width - legendWidth : width"
      :height="height"
      style="border: 0.5px solid black;"
    >
      <defs>
        <pattern
          id="no-data"
          patternUnits="userSpaceOnUse"
          width="5px"
          height="5px"
        >
          <line
            stroke-width="0.5"
            stroke="black"
            x1="0"
            y1="0"
            x2="5"
            y2="5"
            fill="none"
          />
        </pattern>
      </defs>
      <g :key="regionIdx" v-for="(region, regionIdx) in regions">
        <path
          :d="regionToLine(regionIdx)"
          :fill="color[regionIdx]"
          stroke="black"
          :stroke-width="$store.state.view.guidanceEnabled ? '0px' : '1px'"
          :data-stat="statPerRegion[regionIdx]"
        >
          <title v-if="$store.state.view.guidanceEnabled">
            {{ statPerRegion[regionIdx] }}
          </title>
        </path>
      </g>
    </svg>
    <ColorLegend
      v-if="withLegend && $store.state.view.guidanceEnabled"
      :width="legendWidth"
      :height="50"
      :colormap="legendColormap"
      :valueHigh="extent[1]"
      :valueLow="extent[0]"
    />
  </div>
</template>

<script lang="ts">
import { Vue, Component, Prop } from "vue-property-decorator";
import { scaleLinear, scaleSequential, ScaleSequential } from "d3-scale";
import {
  interpolateBlues,
  interpolateGreens,
  interpolateOranges
} from "d3-scale-chromatic";
import { extent } from "d3-array";
import { line } from "d3-shape";
import { KernelGuidance, RegionGuidance, StoreState } from "@/types/store";
import ColorLegend from "@/components/ColorLegend.vue";

class RegionGuidanceClass extends Vue {
  @Prop({ default: "equal-area" }) public strategy!: string;

  @Prop({ default: 1 }) public level!: number;
  @Prop({ default: 200 }) public width!: number;
  @Prop({ default: 0 }) public margin!: number;
  @Prop({ default: "points" }) public analysisTarget!:
    | "kernel-guidance"
    | "diff_cov"
    | "diff_ev"
    | "points";
  @Prop({ default: null }) public kernel!: null | KernelGuidance;
  @Prop({ default: true }) public withLegend!: boolean;

  public height!: number; // computed based on aspect ratio
  public regions!: RegionGuidance[];
  public coordinates!: [number, number][][];
  public statPerRegion!: (number | undefined)[];
  public scaleColor!: ScaleSequential<string>;
  public legendWidth!: number;
  public extent!: [number, number];
}

@Component<RegionGuidanceClass>({
  components: { ColorLegend },
  computed: {
    height: function() {
      const ar = this.$store.getters.bboxAspectRatio("flat");
      return (
        (this.withLegend ? this.width - this.legendWidth : this.width) / ar
      );
    },
    legendWidth: function() {
      return 35;
    },
    legendColormap: function() {
      switch (this.analysisTarget) {
        case "points":
          return "Oranges";
        case "diff_cov":
          return "Greens";
        case "diff_ev":
          return "Blues";
        case "kernel-guidance":
          return "Oranges";
        default:
          throw new Error(this.analysisTarget);
      }
    },
    regions: function() {
      if (["equal-area", "cov-diff", "user"].includes(this.strategy)) {
        const regions =
          (this.$store.state as StoreState).guidance[this.strategy]!.regions[
            this.level
          ] || [];
        return regions;
      }
      const regions =
        (this.$store.state as StoreState).results[this.strategy]!.params
          .regions[0] || [];
      return regions;
    },
    extent: function() {
      return extent(this.statPerRegion as number[]);
    },
    statPerRegion: function() {
      if (this.analysisTarget === "kernel-guidance") {
        return this.kernel!.num_points;
      } else if (this.analysisTarget === "points") {
        return this.regions.map(r => r.num_points);
      } else if (this.analysisTarget === "diff_cov") {
        return this.regions.map(r => r.diff_cov);
      } else if (this.analysisTarget === "diff_ev") {
        return this.regions.map(r => r.diff_ev);
      }
    },
    color: function() {
      return this.statPerRegion.map((r, i) => {
        const data =
          this.analysisTarget === "kernel-guidance"
            ? this.statPerRegion[i]
            : this.regions[i].num_points;

        if (
          data! <
          (this.$store.state as StoreState).view.parameterInput.minNumPoints
        ) {
          return this.scaleColor((undefined as unknown) as number);
        }
        return this.scaleColor(r!);
      });
    },
    scaleColor: function() {
      let interpolator = interpolateBlues;
      if (!this.$store.state.view.guidanceEnabled) {
        return (x: number) => "white";
      }
      switch (this.analysisTarget) {
        case "diff_ev":
          break;
        case "kernel-guidance":
        case "points":
          interpolator = interpolateOranges;
          break;
        case "diff_cov":
          interpolator = interpolateGreens;
          break;
        default:
          throw new Error(this.analysisTarget);
      }

      const color = scaleSequential(interpolator)
        .domain(this.extent)
        .unknown("url(#no-data)");
      return color;
    },
    coordinates: function() {
      const regions = this.regions;
      const extentX = extent(
        regions.flatMap(part => part.patch_flat.map(([x]) => x))
      ) as [number, number];
      const extentY = extent(
        regions.flatMap(part => part.patch_flat.map(([, y]) => -y)) // TODO northern hemisphere specific?
      ) as [number, number];
      const scaleX = scaleLinear()
        .domain(extentX)
        .range([
          this.margin,
          this.width - this.margin - (this.withLegend ? this.legendWidth : 0)
        ]);
      const scaleY = scaleLinear()
        .domain(extentY)
        .range([this.margin, this.height - this.margin]);

      return regions.map(part => {
        return part.patch_flat.map(([x, y]) => [scaleX(x), scaleY(-y)]);
      });
    }
  }
})
export default class RegionGuidanceView extends RegionGuidanceClass {
  regionToLine(regionIdx: number) {
    const region = this.coordinates[regionIdx];
    const l = line()
      .x(d => d[0])
      .y(d => d[1]);
    return l(region);
  }
}
</script>

<style lang="less" scoped>
path {
}
</style>
