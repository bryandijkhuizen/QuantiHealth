## Progressa 2.3.1

- Refresh expired sessions before connecting to Quantivita, with one retry when the server rejects the access token.
- Show connection progress and errors in the consent screen. If sign-in is needed, complete it without losing the pending connection.

## Quantivita 0.7.1

- Compact workout cards with a prominent distance/duration and recorded GPS routes when available.
- Hide unavailable metrics while retaining measured zero power/cadence values.
- Collapsible source details and working undo confirmation for combined activities.

Validation: 14 Progressa authentication/link tests and 3 Quantivita UI tests pass locally. CI validates native workout/authentication tests, all Quantivita unit tests, server tests, and release manifests. Physical-device reconnection requires installing the Progressa update and approving the connection once.
