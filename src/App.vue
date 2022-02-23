<template>
  <div>
    <div v-if="initialized" id="app">
      <Toolbar />
      <router-view />
    </div>
    <div v-else>
      Loading...
    </div>
  </div>
</template>

<script lang="ts">
import { Vue, Component } from "vue-property-decorator";
import Toolbar from "@/components/Toolbar.vue";

@Component({
  components: { Toolbar },
  computed: {
    initialized: function() {
      return this.$store.getters.initialized();
    }
  }
})
export default class Main extends Vue {
  mounted() {
    this.$store.dispatch("fetchInitialData");
  }
}
</script>

<style lang="less">
body {
  font-family: Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  margin: 0;
  padding: 0;
}

#app {
  width: 100vw;
  height: 100vh;
}

#nav {
  padding: 30px;

  a {
    font-weight: bold;
    color: #2c3e50;

    &.router-link-exact-active {
      color: #42b983;
    }
  }
}

</style>
