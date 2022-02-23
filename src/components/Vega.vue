<template>
  <div :data-state="propStateHash + '.' + storeSignalStateHash">
    <div ref="vega"></div>
  </div>
</template>

<script lang="ts">
import * as vg from "vega";
import * as vgLite from "vega-lite";
import { hash } from "@/util/util";
import { Component, Prop, Vue } from "vue-property-decorator";

class VegaClass extends Vue {
  @Prop()
  public spec!: any;
  @Prop()
  public datasets!: any;
  @Prop()
  public signals!: string[];

  public view: any = null;

  public actualSpec!: any;
  public storeSignals!: { [k: string]: any };
}

@Component<VegaClass>({
  computed: {
    actualSpec: function() {
      const spec = {
        ...this.$props.spec,
        datasets: this.$props.datasets,

        width: this.$props.width || this.$props.spec.width,
        height: this.$props.height || this.$props.spec.height
      };
      return spec;
    },
    propStateHash: function() {
      return hash(JSON.stringify(this.actualSpec));
    },
    storeSignals: function() {
      const obj: { [x: string]: any } = {};
      const signals = this.$props.signals || [];
      for (const s of signals) {
        const v = this.$store.getters[s]();
        obj[s] = v;
      }
      return obj;
    },
    storeSignalStateHash: function() {
      return hash(JSON.stringify(this.storeSignals || ""));
    }
  }
})
export default class Vega extends VegaClass {
  @Prop()
  public width!: number;
  @Prop()
  public height!: number;

  mounted() {
    const vgSpec = vgLite.compile(this.actualSpec).spec;
    this.view = new vg.View(vg.parse(vgSpec), {
      logLevel: vg.Warn,
      renderer: "svg"
    });
    this.view.initialize(this.$refs.vega);

    this.view.run();
  }

  updated() {
    this.view.setState({
      signals: this.storeSignals,
      data: this.$props.datasets
    });
    this.view.width(this.actualSpec.width);
    this.view.height(this.actualSpec.height);
    this.view.run();
  }

  beforeDestroy() {
    this.view.finalize();
  }
}
</script>
