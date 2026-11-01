<script setup lang="ts">
const { data: properties, error: propertiesError } = await useCoworkingProperties({ city: 'berlin' })
const { data: rates, error: ratesError } = await useCoworkingRates({ city: 'berlin' })
</script>

<template>
  <div>
    <p id="title">
      {{ properties?.data?.[0]?.title }}
    </p>
    <p id="attribution">
      {{ rates?.data?.attribution }}
    </p>
    <p id="license">
      {{ rates?.data?.license }}
    </p>
    <p id="license-url">
      {{ rates?.data?.licenseUrl }}
    </p>
    <p id="citation">
      {{ properties?.meta?.citation?.text }}
    </p>
    <p id="properties-error">
      {{ propertiesError?.message }}
    </p>
    <p id="rates-error">
      {{ ratesError?.message }}
    </p>
  </div>
</template>
