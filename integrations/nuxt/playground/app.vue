<script setup lang="ts">
const { data: properties, error: propertiesError } = await useCoworkingProperties({ city: 'berlin', pageSize: 3 })
const { data: rates, error: ratesError } = await useCoworkingRates({ city: 'berlin' })
</script>

<template>
  <main>
    <h1>
      <a href="https://coworkingview.com">CoworkingView</a>
    </h1>
    <p v-if="rates?.data?.attribution">
      {{ rates.data.attribution }}
    </p>
    <p v-if="ratesError">
      {{ ratesError.message }}
    </p>
    <p v-else-if="propertiesError">
      {{ propertiesError.message }}
    </p>
    <ul v-else>
      <li
        v-for="space in properties?.data ?? []"
        :key="space.slug"
      >
        {{ space.title }}
      </li>
    </ul>
  </main>
</template>
