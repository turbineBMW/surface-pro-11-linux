# Contributing and test reports

Testing reports from other Surface Pro 11 owners are welcome. This is an
experimental hardware project, so reports should identify the exact model,
SoC/display variant, kernel commit, device-tree file, distribution, and whether
a known-good fallback kernel still boots.

Before posting logs, remove serial numbers, MAC addresses, network names,
usernames, absolute home paths, credentials, face images, and other personal
data. Prefer the smallest log excerpt that demonstrates the problem.

Do not upload or attach:

- Windows driver packages, DLL/SYS/CAB files, or copied configuration files;
- firmware extracted from Windows or another device;
- raw WinDbg traces, memory dumps, symbol files, or decompiler output;
- biometric enrollment data, IR/RGB face captures, or private camera frames;
- code copied from a source whose redistribution license is unknown; or
- former Practical8 patches, bundles, binaries, modules, or payloads.

Hardware observations should be summarized as the minimum factual behavior
needed to reproduce a Linux implementation. When adapting open-source code,
provide its license, copyright notice, upstream URL, exact commit or blob
identity, author credit, and a concise description of local changes.

Material AI assistance must be disclosed with the tool/model name and the
parts it affected. AI output is not accepted as provenance evidence, a
copyright license, or a human review.

The project is not preparing an upstream submission yet. Before an external
patch is merged here, its human contributor will nevertheless be asked to
confirm its source and right to contribute it, normally with a personal
`Signed-off-by` under the Developer Certificate of Origin. Never add another
person's sign-off, review, or test trailer without their permission.
