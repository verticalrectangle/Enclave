# App Review notes — Enclave

Paste the relevant parts into **App Store Connect → App Review Information → Notes**,
and fill in the live demo link before submitting.

---

## What Enclave is

Enclave is a **client (remote control) for a coding session running on the user's
own computer**. The Mac/Linux tool `oh-my-pi` hosts a session and prints a link;
Enclave joins that session over an end-to-end-encrypted WebSocket to show the live
transcript and let the user send messages, stop the run, and answer prompts.

**Nothing executes on the device.** Enclave is a thin client, like an SSH terminal
or a remote-desktop app: all commands run on the user's own host, not in the app.
This is why the app is inert until it is connected to a host (Guideline 2.5.2 is
not engaged — no code is downloaded or executed on device).

## ▶︎ How to test it (required — the app is empty without a host)

The app cannot be exercised without a live host to join, so we provide one:

1. Open the app → **Pair a box** (or the **＋ PAIR A BOX** button).
2. Paste this demo link (a host we keep running for review):

   ```
   <PASTE A LIVE DEMO COLLAB LINK HERE — keep the host up for the review window>
   ```

3. Tap **Connect**. The live transcript loads; you can type a message and watch the
   agent respond, tap **Stop**, and open the **Activity** and **Trust** tabs.

If the link ever stops responding during review, please contact us at
`<support email>` and we will restart the demo host immediately.

## Encryption

Enclave secures its own traffic with standard **AES-256-GCM** (Apple CryptoKit).
`ITSAppUsesNonExemptEncryption` is set to `false` — the app uses only standard
encryption in a way that qualifies for the export exemption; it implements no
proprietary or non-standard cryptography. (If a formal self-classification is
requested, we will file it.)

## Privacy

- No account, no sign-up. The user pastes a link they generated on their own machine.
- No analytics, no tracking, no third-party SDKs. **Data Not Collected.**
- Session content is end-to-end encrypted; the relay only ever sees ciphertext.

## Content / age rating

The remote agent produces text on the user's own private session (not a public
feed). There is no user-to-user social surface. We have rated the app accordingly;
happy to adjust if you'd prefer a higher rating for AI-generated text.

## Notifications / Live Activity

- A **local** notification fires when the host is waiting on the user's answer.
- A **Live Activity** (lock screen + Dynamic Island) mirrors the connected session.
- Remote push is not enabled in this build.
