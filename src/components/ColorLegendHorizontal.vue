<template>
  <div>
    <!-- <div class="legend-container">
      <span class="legend">← more similar</span>
      <span class="legend">less similar →</span>
    </div> -->
    <div class="d-flex flex-column" style="gap: 2px">
      <!--   <img :src="scaleImgBinned" height="15" :width="width" /> -->
      <img :src="scaleImg" height="15" :width="width" />
    </div>
    <!--  <div class="legend-container">
      <span class="legend">{{ extremeValues[1] }}</span>
      <span class="legend">{{ extremeValues[0] }}</span>
    </div> -->
  </div>
</template>

<script lang="ts">
import { Component, Prop, Vue } from "vue-property-decorator";
import {
  interpolateBlues,
  interpolatePurples,
  interpolateGreens,
  interpolateOranges
} from "d3-scale-chromatic";

function rampImg(scale: (x: number) => string, n = 256) {
  const canvas = document.createElement("canvas");
  canvas.width = n;
  canvas.height = 1;
  const context = canvas.getContext("2d")!;
  const [start, end] = [1, 0];
  for (let i = 0; i < n; ++i) {
    const interpolate = end - (i * (end - start)) / n;
    context.fillStyle = scale(interpolate);
    context.fillRect(i, 0, 1, 1);
  }
  const url = canvas.toDataURL();
  return url;
}
class ColorLegendHorizontalClass extends Vue {
  @Prop({ default: 200 })
  public width!: number;
  @Prop({ default: 10 })
  public height!: number;

  @Prop()
  public color!: string;

  public scale!: (x: number) => string;
}
@Component<ColorLegendHorizontalClass>({
  computed: {
    scale: function() {
      switch (this.color) {
        case "Blues":
          return interpolateBlues;
        case "Greens":
          return interpolateGreens;
        case "Oranges":
          return interpolateOranges;
        case "Purples":
          return interpolatePurples;
        default:
          throw new Error(this.color);
      }
    },

    scaleImg: function() {
      return rampImg(this.scale, 256);
    }
  }
})
export default class ColorLegendHorizontal extends ColorLegendHorizontalClass {}
</script>
<style lang="less" scoped></style>
