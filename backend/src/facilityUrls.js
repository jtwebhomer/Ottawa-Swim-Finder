export function facilityUrl(facilityId) {
  return `https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/${facilityId}`;
}

export function randomFacilityDelayMs() {
  return 1000 + Math.floor(Math.random() * 1000);
}
