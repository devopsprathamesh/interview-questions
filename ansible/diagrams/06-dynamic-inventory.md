# Diagram 6: Dynamic Inventory Architecture (AWS)

Referenced from [`docs/inventory-and-variables.md` §1](../docs/inventory-and-variables.md#1-static-vs-dynamic-inventory) and [Lab 3](../labs/lab-03-dynamic-inventory/).

```mermaid
flowchart TD
    Playbook["ansible-playbook -i inventory/aws_ec2.yml site.yml"] --> Plugin["amazon.aws.aws_ec2\ninventory plugin"]
    Plugin -->|"DescribeInstances API call,\nfiltered by tags/state"| AWS[(AWS EC2 API)]
    AWS --> Plugin
    Plugin --> KeyedGroups["keyed_groups:\nrole_webserver, role_database,\naz_us-east-1a, ..."]
    KeyedGroups --> Compose["compose:\nansible_host = private_ip_address"]
    Compose --> ResolvedInventory[Live, current host list\nand group membership]
    ResolvedInventory --> GroupVars["group_vars/role_webserver.yml\napplied automatically"]
    ResolvedInventory --> Playbook2[Playbook tasks execute\nagainst resolved hosts]
```

**Key points:**
- Inventory is resolved **live, every run** — never stale relative to what's actually running in AWS, unlike a hand-maintained static file.
- `keyed_groups` and `compose` let tag-based cloud metadata drive group membership and connection details automatically — no manual inventory maintenance as instances launch/terminate.
- A live API dependency means an AWS API outage or IAM permission gap makes the inventory unavailable entirely — a real, if usually minor, availability trade-off against a static file's independence from any live API call.
