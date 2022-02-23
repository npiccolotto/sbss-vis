<template>
  <div
    class="single-map"
    v-on:mouseenter="setActive"
    v-on:mouseleave="setInactive"
    :style="{
      width: '100%',
      height: 'calc(100vh - 71px)',
      border: isActiveMap ? '1px solid red' : '1px solid black'
    }"
  >
    <l-map
      @update:bounds="onUpdateBounds"
      style="width: 100%; height:100%;"
      :bounds="bounds"
    >
      <l-tile-layer
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      ></l-tile-layer>

      <l-layer-group>
        <l-marker
          v-for="(loc, i) in $store.state.dataset.locations"
          :key="i"
          :lat-lng="loc"
          ><l-icon
            :icon-size="[16, 16]"
            :icon-anchor="[8, 8]"
            :icon-url="iconUrlLocation"
          >
          </l-icon
        ></l-marker>
      </l-layer-group>
    </l-map>
  </div>
</template>

<script lang="ts">
import { latLngBoundsToArray } from "@/util/geo";
import { Vue, Prop, Component } from "vue-property-decorator";

class MapClass extends Vue {
  public isActiveMap = false;
}

@Component<MapClass>({
  computed: {
    bounds: function() {
      return this.$store.state.view.bounds;
    },
    iconUrlLocation: function() {
      return process.env.VUE_APP_PUBLIC_PATH + "images/icon-location.png";
    }
  }
})
export default class Map extends MapClass {
  onUpdateBounds(bounds: any) {
    if (this.isActiveMap) {
      const b = latLngBoundsToArray(bounds);
      this.$store.dispatch("setBounds", b);
    }
  }

  setActive() {
    this.isActiveMap = true;
  }
  setInactive() {
    this.isActiveMap = false;
  }
}
</script>

<style lang="less" scoped>
.single-map {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
</style>
