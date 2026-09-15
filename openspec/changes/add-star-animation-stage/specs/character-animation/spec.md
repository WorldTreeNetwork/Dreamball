## ADDED Requirements

### Requirement: Explicit animation clock
The player SHALL sample declarative curves independently of the renderer and causal history timeline. Seeking SHALL cancel an active reaction without replaying triggers.

#### Scenario: Touch reaction
- GIVEN a ready Star stage
- WHEN the user touches Star or activates Say hello
- THEN one bounce/spin starts and returns to idle; touches during the reaction do not queue reactions.

### Requirement: Bounded rendering
The stage SHALL limit continuous animation to at most 30 frames per second, pixel ratio to 1.5 and longest backing-store dimension to 1200 pixels. It SHALL suspend recurring rendering when paused, hidden or offscreen, and dispose resources when unmounted.

#### Scenario: Reduced motion
- GIVEN reduced motion is requested
- WHEN the stage opens or Star receives a touch
- THEN the stage remains still and acknowledges the touch in text.

### Requirement: Capsule verification
The demo SHALL require a successful signed-capsule verification before passing its mesh URL to the stage.

#### Scenario: Invalid capsule
- GIVEN corrupted capsule bytes
- WHEN the demo opens
- THEN it shows an error and does not mount a renderer.
