import Vue from "vue";
import App from "./App.vue";
import router from "./router";
import * as vega from "vega";
import store from "./store";
import VTooltip from "v-tooltip";
import { LMap, LTileLayer, LMarker, LLayerGroup, LIcon } from "vue2-leaflet";
import { BootstrapVue, BootstrapVueIcons } from "bootstrap-vue";
import "bootstrap/dist/css/bootstrap.css";
import "bootstrap-vue/dist/bootstrap-vue.css";
import "leaflet/dist/leaflet.css";
import "@geoman-io/leaflet-geoman-free/dist/leaflet-geoman.css";

import * as d3Scale from "d3-scale";

Vue.use(BootstrapVue);
Vue.use(BootstrapVueIcons);
Vue.use(VTooltip);
Vue.component("l-map", LMap);
Vue.component("l-tile-layer", LTileLayer);
Vue.component("l-marker", LMarker);
Vue.component("l-layer-group", LLayerGroup);
Vue.component("l-icon", LIcon);

Vue.config.productionTip = false;

new Vue({
  router,
  store,
  render: h => h(App)
}).$mount("#app");
