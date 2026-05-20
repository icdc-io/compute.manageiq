# Compute ManageIQ

**Compute ManageIQ** is the cloud compute management component of the [ICDC Platform](https://github.com/icdc-io). It is a customized fork of [ManageIQ](https://github.com/ManageIQ/manageiq), adapted and extended by the ICDC team since 2019 to serve as the compute orchestration and infrastructure management layer of the platform.

## Overview

This component provides hybrid IT management capabilities including discovery, monitoring, provisioning, policy enforcement, and automation across virtual machines, containers, networks, and storage — all integrated within the ICDC platform architecture.

**Feature areas:**

- **Insight** — Discovery, monitoring, utilization, performance reporting, analytics, chargeback, and trending
- **Control** — Security, compliance, alerting, and policy-based resource and configuration management
- **Automate** — IT process, task and event automation, provisioning, workload management, and orchestration
- **Integrate** — Systems management, event consoles, CMDB, RBA, and web services

## ICDC Platform Context

Compute ManageIQ is one of several components that together form the ICDC Platform. It exposes APIs and internal interfaces consumed by other platform services and is not intended to be deployed standalone in an ICDC environment.

For platform-level documentation and deployment guides, refer to the main ICDC Platform repository.

## Getting Started

### Prerequisites

- Ruby 2.7+
- PostgreSQL 13+
- Node.js 14+

### Development Setup

```bash
git clone https://github.com/icdc-io/compute-manageiq.git
cd compute-manageiq
bin/setup
```

Refer to the [ManageIQ developer documentation](https://github.com/ManageIQ/guides) for detailed setup instructions — the upstream guides apply to this fork unless otherwise noted in this repository.

## Contributing

Issues and pull requests are welcome. Please open an issue before submitting a large change so the approach can be discussed first.

## Upstream

This repository is a fork of [ManageIQ](https://github.com/ManageIQ/manageiq), an open-source management platform originally created and maintained by the ManageIQ Authors. The ICDC team began maintaining this fork in 2019. We gratefully acknowledge the upstream contributors.

- Upstream project: https://github.com/ManageIQ/manageiq
- Upstream documentation: https://www.manageiq.org
- Upstream community: https://gitter.im/ManageIQ/manageiq

## License

ICDC-specific modifications and extensions are Copyright 2019–2026 IBA Group a.s. and are licensed under the [Apache License, Version 2.0](LICENSE.txt).

The original ManageIQ source is Copyright 2014–2019 ManageIQ Authors and is also licensed under the Apache License, Version 2.0.

See [LICENSE.txt](LICENSE.txt) for the full license text.
