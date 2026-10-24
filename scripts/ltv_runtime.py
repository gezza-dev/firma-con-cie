# SPDX-License-Identifier: BSD-3-Clause
"""Select only the private JVMs explicitly supported by the DSS runtime."""
import platform


def runtime_architecture(system=None, machine=None):
    system = system or platform.system()
    machine = (machine or platform.machine()).lower()
    arch = {'amd64': 'x86_64', 'x64': 'x86_64', 'aarch64': 'arm64'}.get(machine, machine)
    supported = {
        ('Darwin', 'arm64'): 'macos-arm64',
        ('Darwin', 'x86_64'): 'macos-x86_64',
        ('Windows', 'x86_64'): 'windows-x86_64',
        ('Linux', 'x86_64'): 'linux-x86_64',
        ('Linux', 'arm64'): 'linux-arm64',
    }
    try:
        return supported[system, arch]
    except KeyError:
        raise ValueError('Unsupported private DSS JVM: ' + system + '/' + machine) from None
