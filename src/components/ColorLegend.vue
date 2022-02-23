<template>
  <svg :width="width" :height="height">
    <g :transform="'translate(' + margin[3] + ',' + margin[0] + ')'">
      <g transform="translate(1,0)">
        <text
          :x="width - margin[1] - margin[3]"
          y="5"
          font-size="6"
          font-family="monospace"
        >
          <title>{{ valueHighFormatted }}</title>
          {{ valueHighFormatted }}
        </text>
        <text
          :x="width - margin[1] - margin[3]"
          :y="height - margin[0] - margin[2]"
          font-size="6"
          font-family="monospace"
        >
          <title>{{ valueLowFormatted }}</title>
          {{ valueLowFormatted }}
        </text>
      </g>
      <image
        :x="margin[3]"
        :y="margin[0]"
        :width="width - margin[1] - margin[3]"
        :height="height - margin[0] - margin[2]"
        preserveAspectRatio="none"
        :xlink:href="dataUrl"
      />
    </g>
  </svg>
</template>

<script lang="ts">
import { Vue, Component, Prop } from "vue-property-decorator";
import {
  interpolateBlues,
  interpolatePurples,
  interpolateGreens,
  interpolateOranges
} from "d3-scale-chromatic";
import { formatNumber } from "@/util/format";

class ColorLegendClass extends Vue {
  @Prop({ default: () => [0, 30, 0, 0] })
  public margin!: [number, number, number, number];

  @Prop({ default: "Blues" })
  public colormap!: string;

  @Prop({ default: 256 })
  public resolution!: number;

  @Prop({ default: 10 })
  public width!: number;

  @Prop({ default: 200 })
  public height!: number;

  @Prop({ default: false })
  public ltr!: boolean;

  @Prop({ default: 0 })
  public valueHigh!: number;

  @Prop({ default: 0 })
  public valueLow!: number;

  public color!: (x: number) => string;
}

function rampImg(color: (i: number) => string, n = 256, ltr = false) {
  const canvas = document.createElement("canvas");
  canvas.width = ltr ? n : 1;
  canvas.height = ltr ? 1 : n;
  const context = canvas.getContext("2d")!;
  for (let i = 0; i < n; ++i) {
    const interpolate = ltr ? i / (n - 1) : 1 - i / (n - 1);
    context.fillStyle = color(interpolate);
    const fillArgs: [number, number, number, number] = ltr
      ? [i, 0, 1, 1]
      : [0, i, 1, 1];
    context.fillRect(...fillArgs);
  }
  const url = canvas.toDataURL();
  return url;
}

@Component<ColorLegendClass>({
  computed: {
    valueHighFormatted: function() {
      return formatNumber(this.valueHigh);
    },
    valueLowFormatted: function() {
      return formatNumber(this.valueLow);
    },
    color: function() {
      switch (this.colormap) {
        case "Blues":
          return interpolateBlues;
        case "Greens":
          return interpolateGreens;
        case "Oranges":
          return interpolateOranges;
        case "Purples":
          return interpolatePurples;
        default:
          throw new Error(this.colormap);
      }
    },
    dataUrl: function() {
      return rampImg(this.color, this.resolution, this.ltr);
    }
  }
})
export default class ColorLegend extends ColorLegendClass {}
</script>

<style lang="less" scoped></style>
