On demand ATS testing
=====================

[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

## Concepts

We use `podman`, a docker-like utility that's able to run `systemd`. We
create one NGFW container and one client container, and connect them
through custom networks so that the client traffic goes through the
NGFW.

Containers are not meant to be reused, but new ones should instead be
started for each test run.

Right now the only requirement is a Buster host running an NGFW kernel:
`buster-host-setup.sh` will set that up.

## Quick start


### Setup the host

Starting from a vanilla Buster install, running a vanilla Debian kernel:

```bash
$ ./bin/buster-host-setup.sh
```

### Create images

Use `bin/ats-build-containers.sh`:

```bash
$ ./bin/ats-build-containers.sh <target_distribution> <image_name>
```

For instance:

```bash
$ ./bin/ats-build-containers.sh current ngfw:16.3.0-20210302
```

### Start containers from those images

```bash
$ ./bin/ats-start-containers.sh <image_name>
```

With the image name used above, this would result in:

```bash
$ ./bin/ats-start-containers.sh ngfw:16.3.0-20210302
loading required kernel modules: done
creating podman networks: done
starting container ats-ngfw-20210302: done
setting sysctls: done
waiting for UVM startup before injecting network settings: .................... done
assigning license: {"status":true,"message":"Operation successful! addLicense, f2c7-825f-84cf-f452, UN-82-PRM-0010-MONTH, , 03\/02\/2021, "} done
starting container ats-client-20210302: done
waiting for ATS client to get a DHCP lease from NGFW: ............ done (192.168.2.129)
```

### Run the ATS test suite

```bash
$ ./bin/ats-run-tests.sh <container_name>
```

With the container created above:

```bash
$ ./bin/ats-run-tests.sh ngfw:16.3.0-20210302
===================================================================================================================================================== test session starts =====================================================================================================================================================
platform linux -- Python 3.7.3, pytest-3.10.1, py-1.7.0, pluggy-0.8.0 -- /usr/bin/python3
cachedir: .pytest_cache
rootdir: /usr/lib/python3/dist-packages/tests, inifile:
collected 866 items / 170 deselected
../../../usr/lib/python3/dist-packages/tests/test_ad_blocker.py::AdBlockerTests::test_010_clientIsOnline PASSED
../../../usr/lib/python3/dist-packages/tests/test_ad_blocker.py::AdBlockerTests::test_011_license_valid PASSED
../../../usr/lib/python3/dist-packages/tests/test_ad_blocker.py::AdBlockerTests::test_021_adIsBlocked PASSED
[...]
```

### Visualize the results

ATS uses `pytest`, which can export its results in `JUnit`-compatible
format. There are many visualization frameworks for those, right now our
PoC uses [Allure](https://github.com/allure-framework/allure2).

Here's an example of an Allure report:
  http://ats-iqd.untangle.int/ats-on-demand/16.2.2/20210224T132836

## TODO/bugs

- [ ] only NGFW >= 16.3 are testable, as the uvm and various
      dependencies had to be adjusted in order to run in a container.

- [ ] bin/* tools do not expose a stable CLI interface. They will be
      rewritten in python soon, with proper handling for more CLI
      parameters.

- [ ] ability to run only a subset of the ATS tests (only doable
      manually right now with something like `podman exec -it
      ats-ngfw-16.3.0 pytest-3 -v --runtests-host=192.168.2.147
      --skip-instantiated=true -m web_cache
      /usr/lib/python3/dist-packages/tests`
	  
- [ ] some tests fail in a container environment, but succedd in the
      official QA ATS infrastructure. The full list list of those tests
      is being assembled, so they can be investigated one by one.
	  
- [ ] from time to time, the UVM becomes unresponsive and the tests that
      run during this timeframe error out.
	  
- [ ] performance: building the `podman` images can take a long time,
      and the current `uvm-base` vs `final-image` split is probably not
      the most efficient. Right now its only benefit is avoiding an
      upgrade of existing Untangle packages.
	  
- [ ] manually loading kernel modules on the host is error-prone:
      `ats-start-container.sh` will need to be adjusted each time we
      require a new kernel module. This doesn't happen often at all, but
      it still is a problem.
	  
- [ ] the client container runs with extra capabilities just so it can
      get a DHCP lease from the NGFW. We could instead manually assign
      it an address in `192.168.2.0/24`.
	  
- [ ] reports should be automatically uploaded to `ats-iqd`, or some
      other server.

- [ ] we need some webservice/scheduler so on-demand ATS jobs can be
      enqueued and then executed, depending on various events (MR on
      GitHub, etc)

## Flaky tests

Those are failing in a the containerized environment, but not in the
official QA infrastructure:

- AdBlockerTests::test_023_eventlog_blockedAd
- AdBlockerTests::test_025_userDefinedAdNotBlocked
- AdBlockerTests::test_027_passSiteEnabled
- AdBlockerTests::test_029_passClientEnabled
- BandwidthControlTests::test_012_qos_limit
- BandwidthControlTests::test_013_qos_bypass_custom_rules_tcp
- BandwidthControlTests::test_020_severely_limited_tcp
- BandwidthControlTests::test_050_severely_limited_web_filter_flagged
- BandwidthControlTests::test_060_host_quota
- BandwidthControlTests::test_061_user_quota
- CaptivePortalTests::test_070_login_redirect_using_hostname
- ConfigurationBackupTests::test_020_backupNow
- ConfigurationBackupTests::test_140_compare_cloud_backup
- FirewallTests::test_051_intfDst
- FirewallTests::test_052_intfWrongIntf
- FirewallTests::test_053_intfCommas
- NetworkTests::test_020_port_forward_80
- NetworkTests::test_07*_ftp_modes*
- ShieldTests::test_020_shieldDetectsNmap
- ShieldTests::test_021_shieldOffNmap
- UvmTests::test_030_test_smtp_settings
- UvmTests::test_060_customized_email_alert
- VirusBlocker::test_009_bdamserverIsRunning takes forever, fails with "Trying to download the updates from http://bd.untangle.com/av64bit [...] ERROR: [...] Connection timeout (FFFFF7C4)
- WebFilterTests::test_010_0000_rule_condition_dst_intf
- WebFilterTests::test_301_block_QUIC
- WebFilterTests::test_700_safe_search_enabled
- WebMonitorTests::test_015_porn_subdomain_and_url_is_blocked_by_default
- WireGuardVpnTests::test_020_createWireGuardTunnel
