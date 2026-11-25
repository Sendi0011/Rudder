# Demo video outline

Target runtime: 4:55. The segment budget below adds to 5:00; trim five seconds of dead air in the
close so the finished file is under five minutes. Record in your own voice. No text-to-speech, voice
cloning or synthetic narration.

| Time | Segment | What is on screen | What you say |
| --- | --- | --- | --- |
| 0:00–0:40 | Problem | The corridor chart. A range drawn away from the TWAP; a rejected move in signal red. | Curated liquidity delegates range choices. The question is how to let a curator steer while making the delegation bounded and the exit unconditional. |
| 0:40–1:30 | How it works | Registry envelope, vault, hook, then the five steps from `/docs/how-it-works`. | The envelope lives on-chain. Tightening is immediate, loosening waits 24 hours, the hook checks adds, the vault checks rebalances, and exits never read the oracle. Ranking uses alpha versus holding, not size. |
| 1:30–3:30 | Live demo | Wallet connect on chain 1301, public test-token mint, deposit with share preview, the corridor chart updating, withdraw, then `/proof`: choose a proposed range and run the live simulation against the deployed vault. | Show the deposit and exit. Then say plainly: this is a live simulation of the deployed contract, not a recording. Run the simulation, read the decoded revert and name the limit that broke. No transaction is sent. |
| 3:30–4:30 | Comparison and limits | Evidence table, mutation table, placebo results, known limitations and the prior-art table. | Read the placebo number as it is: the reactive mean did not beat the placebo mean. These are local measurements, not live performance. Rudder is not audited; the comparison covers the datasets we searched, not the whole ecosystem. |
| 4:30–4:55 | Close | Protocol addresses and the docs route. | The contracts are on Unichain Sepolia, the sources and evidence are in the repository, and every page links to the markdown it came from. |

## Recording checklist

- [ ] Record your own voice in one take per section; listen back and rerecord unclear lines.
- [ ] No synthetic voices, TTS, voice clones or generated narration anywhere in the track.
- [ ] Use a clean microphone; no clipping, echo or background music under speech.
- [ ] Hide browser extensions and notifications before capturing the screen.
- [ ] Do not show a private key, seed phrase, `.env` file, RPC URL or signer prompt on screen.
- [ ] Do not broadcast a transaction during capture; the proof segment is `simulateContract` only.
- [ ] Show the chain selector (Unichain Sepolia, 1301) before the wallet flow.
- [ ] Show the live simulation label, decoded revert and broken limit in the same shot.
- [ ] Show the evidence links and the not-audited limit before the close.
- [ ] Export under 4:55, add captions from your own transcript, and verify playback has no console or audio errors.

---

Rendered from commit 3212ad666f4f528fc441666739df78ba7be5182b · [View source](https://github.com/Sendi0011/Rudder/blob/3212ad666f4f528fc441666739df78ba7be5182b/docs/VIDEO.md)
