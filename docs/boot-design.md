# First Linux boot decision

The first payload runs from RAM and exposes a USB ACM shell. The kernel does
not enumerate eMMC. Display, touch, networking and Omarchy follow after this
boot path is observed on the frame.

Two independent design drafts were produced under `build/design/`:

| Candidate | Strongest property | Limitation |
| --- | --- | --- |
| A: minimal headless board | Small dependency chain with USB diagnostics | Needed build reproducibility and exact power-tree corrections |
| B: complete board with disabled peripheral nodes | One authoritative board description for later work | Added unresolved device contracts, NCM, DHCP and HTTP before boot was proven |

Select A and retain B's single-DTS ownership rule: extend
`kernel/dts/rk3326-frame157.dts` as each hardware path is verified. Keep uncertain
electrical facts in documentation rather than inactive placeholder nodes.

An independent judge recommended this selection. All candidates and the
successful judge used `gpt-5.6-sol`; the attempted cross-provider judge failed
with an API rate limit before reviewing anything. The review is independent by
agent, not by provider. The parent read both drafts and the judge's findings.

Required implementation corrections:

- Preserve the live RK809 input supplies, voltage ranges and boot/always-on
  flags, including this board's switch assignments. LDO3 is named
  `vcc1v0_soc`. Omit unverified initial-mode translation and suspend changes.
- Enable only the first-boot dependency chain: RK809, I/O domains, SD at
  25 MHz and USB peripheral. Keep eMMC/SDIO disabled and leave display/touch
  out of this unit.
- Pin and verify kernel source, clean old build products, record provenance,
  and assert boot-critical kernel options in the merged configuration.
- Build a static AArch64 BusyBox initramfs with a real controlling-terminal
  shell. Mount only pseudo-filesystems automatically. Use one ACM function.
- Inspect the final DTB, initramfs, extlinux paths and image contents. Save
  hashes and schema/build output. Compilation proves artifact construction;
  only the frame's USB console can prove the boot path.

Reject NCM/DHCP/HTTP and premature display/touch integration. Do not add a
dummy IDB signature or replacement loader to removable media. The vendor
`rkimgtest` source checks sector 64, so extlinux-only SD selection remains
uncertain despite U-Boot containing distro support. Resolve that selection with
source evidence and a controlled test after the offline backup finishes.

Existing user authorization covers this continuation and reversible recovery
probes. Completing and verifying the offline backup is an evidence prerequisite
before a boot experiment, not a new permission request.

The implementation and final artifact require an independent review after the
build. Hardware acceptance remains: observe the USB success marker and shell,
verify no eMMC device is exposed, and return to stock boot after card removal.
