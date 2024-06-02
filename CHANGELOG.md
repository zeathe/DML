
CHANGELOG
=========

2.3.0 ( - zeathe)
-----------------

### Added

* Typical Markdown info files in root of Repo
* ownedZones: toggleVis? input flag

### Changed

* PERFORMANCE TUNE: Updated ownedZones update() logic to skip all calculations 
  for unit populations for unbeatable zones.
* ownedZones: Fixed some outputs to look at local and configuration zone for
  outputs... the idea being that verbose->true in a config zone should
  override output, but verbose->false in a local zone should not override the
  config zone (debugging).

### Deprecated

### Removed

### Fixed

* RND: Fized 'done!' signal that wouldn't kick if end of random was reached
  mid-cycle.

### Security



2.2.3 (Release - csofanz)
-------------------------

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

