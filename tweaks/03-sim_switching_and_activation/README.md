# SIM switching and activation

This merged topic owns guarded activation, rollback, connectivity proof and
the RM500U CFUN/GPIO fast-switch path.

## Cumulative changed files

- `/etc/init.d/cellular`
- `/usr/sbin/simmanager-control`
- `/usr/sbin/simmanager-fast-switch`
- `/usr/sbin/simmanager-sms`

The active cumulative implementation protects configuration with checkpoints,
uses bounded interface-bound Internet proof, prevents inherited AT locks,
validates GPIO read-back, uses the dedicated CFUN control port, accepts a
trailing ICCID padding nibble and retains the vendor hard-power-cycle fallback.

## Source stages merged

1. `sim_switch_timing_fix` — reverted attempt retained only in legacy history.
2. `sim_switch_fast_connectivity_acceptance`
3. `rm500u_cfun_gpio_fast_switch`
4. `simmanager_at_lock_inheritance_fix`
5. `rm500u_gpio_readback_acceptance_fix`
6. `rm500u_cfun_control_port_fix`
7. `rm500u_iccid_padding_fix`

The cumulative `changed/` tree does not apply the reverted timing attempt.
That earlier stage remains available through Git history.
