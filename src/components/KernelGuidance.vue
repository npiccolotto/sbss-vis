<template>
  <div
    :style="{
      display: 'grid',
      'grid-template-columns': width - legendWidth + 'px ' + legendWidth + 'px',
      'grid-gap': '5px',
      'align-items': 'center'
    }"
  >
    <svg :width="width - legendWidth" :height="height">
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
      <g>
        <rect
          v-for="k in kernelViews"
          :key="
            k.kernel.depth + '.' + k.kernel.region_index + '.' + k.kernel.index
          "
          :x="k.x"
          :y="k.y"
          class="kernel"
          :width="k.width"
          :height="k.height"
          :fill="!$store.state.view.guidanceEnabled ? 'gray' : k.fill"
          :stroke="sameKernel(k.kernel, selectedKernel) ? 'white' : 'none'"
          :data-depth="k.kernel.depth"
          :data-kernel-index="k.kernel.index"
          :data-region-index="k.kernel.region_index"
          :data-fill-stat="k.fillStatValue"
          @click="handleKernelClick(k.kernel)"
          :style="{ cursor: interactive ? 'pointer' : 'default' }"
        >
          <title v-if="$store.state.view.guidanceEnabled">
            {{ formatRing(k.kernel.ring) }}: {{ formatNumber(k.fillStatValue) }}
          </title>
        </rect>
      </g>
      <g
        class="axis"
        ref="axis"
        :transform="'translate(0,' + (height - margin - axisHeight) + ')'"
      ></g>
    </svg>
    <ColorLegend
      v-if="$store.state.view.guidanceEnabled"
      :width="legendWidth"
      :height="height - margin"
      colormap="Oranges"
      :x="150"
      :y="50"
      :valueHigh="extent[1]"
      :valueLow="extent[0]"
    />
  </div>
</template>

<script lang="ts">
import { KernelGuidance, StoreState } from "@/types/store";
import { Vue, Component, Prop } from "vue-property-decorator";
import {
  scaleLinear,
  ScaleLinear,
  scaleSequential,
  ScaleSequential,
  ScaleBand,
  scaleBand
} from "d3-scale";
import { extent } from "d3-array";
import { axisBottom } from "d3-axis";
import { formatRing, formatNumber } from "@/util/format";
import * as math from "mathjs";
import { select } from "d3-selection";
import { interpolateOranges } from "d3-scale-chromatic";
import { sameKernel } from "@/util/util";
import ColorLegend from "@/components/ColorLegend.vue";

class KernelGuidanceClass extends Vue {
  @Prop({ default: "equal-area" }) public strategy!: string;

  @Prop({ default: 1 }) public level!: number;
  @Prop({ default: 400 }) public width!: number;
  @Prop({ default: 200 }) public height!: number;
  @Prop({ default: 2 }) public margin!: number;
  @Prop({ default: true }) public interactive!: boolean;

  public coordinates!: [number, number][][];
  public kernels!: KernelGuidance[];
  public range!: [number, number];
  public axisHeight = 6;
  public legendWidth = 35;

  public baseData!: KernelGuidance[];
  public stat(k: KernelGuidance) {
    return 0;
  }
  public scaleX!: ScaleLinear<number, number>;
  public scaleY!: ScaleBand<string>;
  public extent!: [number, number];
  public scaleColor!: ScaleSequential<string>;
}

@Component<KernelGuidanceClass>({
  components: { ColorLegend },
  computed: {
    selectedKernel: function() {
      return this.$store.getters.guidanceFocus(this.strategy).kernel;
    },
    range: function() {
      return (this.$store.state as StoreState).guidance["equal-area"]
        .kernels[0][0].ring;
    },
    kernels: function() {
      const state = this.$store.state as StoreState;
      if (["equal-area", "cov-diff", "user"].includes(this.strategy)) {
        const kernels = state.guidance[this.strategy].kernels;
        return kernels.length > 0 ? kernels[this.level] : [];
      }
      const kernels = state.results[this.strategy].params.kernels[0];
      return kernels;
    },
    scaleX: function() {
      const scaleX = scaleLinear()
        .domain(this.range)
        .range([this.margin, this.width - this.margin - this.legendWidth]);
      return scaleX;
    },
    scaleY: function() {
      const scaleY = scaleBand()
        .domain(this.kernels.map(k => k.depth + ""))
        .range([this.margin, this.height - this.margin - this.axisHeight]);
      return scaleY;
    },
    baseData: function() {
      // comparewithin = true -> compare kernels WITHIN this regionalization level
      // comparewithin = false -> compare kernels BETWEEN ALL regionalization levels
      const compareWithin = true; // false = compare between
      const baseData = compareWithin
        ? this.kernels
        : (this.$store.state as StoreState).guidance[
            this.strategy
          ].kernels.flatMap(x => x);
      return baseData;
    },
    extent: function() {
      const data = this.baseData.map(k => this.stat(k));
      const ext = (extent(data) as unknown) as [number, number];
      return ext;
    },
    scaleColor: function() {
      const scaleColor = scaleSequential(interpolateOranges)
        .domain(this.extent)
        .unknown("url(#no-data)");
      return scaleColor;
    },
    kernelViews: function() {
      const rectForKernel = (kernel: KernelGuidance) => {
        const [x1, x2] = kernel.ring.map(s => this.scaleX(s));
        const y1 = this.scaleY(kernel.depth + "");
        const y2 = y1! + this.scaleY.bandwidth();
        const stat = this.stat(kernel);
        let fill = this.scaleColor(stat);
        if (
          Math.min(...kernel.num_points) <
          (this.$store.state as StoreState).view.parameterInput.minNumPoints
        ) {
          fill = this.scaleColor((undefined as unknown) as number);
        }

        return {
          x: x1,
          width: x2 - x1,
          y: y1,
          height: y2 - y1!,
          fillStatValue: stat,
          fill
        };
      };
      console.log(this.strategy, this.kernels);
      return this.kernels.map(k => ({
        ...rectForKernel(k),
        kernel: k
      }));
    }
  }
})
export default class KernelGuidanceView extends KernelGuidanceClass {
  stat(kernel: KernelGuidance) {
    const data = kernel.num_points.map(ev => (ev === null ? undefined : ev));
    const stat = data.every(x => !x)
      ? undefined
      : math.median(...(data.filter(x => !!x) as number[]));
    return stat;
  }
  formatRing(ring: [number, number]) {
    return formatRing(ring);
  }
  formatNumber(x: number) {
    return formatNumber(x);
  }
  handleKernelClick(k: KernelGuidance) {
    this.$store.dispatch("setParameterInputFocus", {
      strategy: this.strategy,
      focus: {
        regionalizationLevel: k.region_depth,
        kernelDepth: k.depth,
        kernelIndex: k.index
      }
    });
  }
  sameKernel(k1: KernelGuidance, k2: KernelGuidance) {
    return sameKernel(k1, k2);
  }

  drawAxis() {
    const el = this.$refs.axis as Element;
    const axisB = axisBottom(this.scaleX)
      .ticks(5)
      .tickSize(3);
    select(el)
      .call(axisB as any)
      .call(g =>
        g
          .selectAll(".tick text")
          .attr("dy", 2)
          .style("font-size", "6px")
          .style("font-family", "monospace")
      );
  }

  mounted() {
    this.drawAxis();
  }

  updated() {
    this.drawAxis();
  }
}
</script>

<style lang="less" scoped>
rect {
  stroke: gray;
  stroke-width: 0px;

  &.kernel:hover {
    stroke: white;
    fill: gray;
    stroke-width: 1px;
  }
}

.axis .tick text {
  font-size: 6px;
  font-family: monospace;
}
</style>
