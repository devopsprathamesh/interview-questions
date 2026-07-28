"""Custom ansible-lint rule: no task may disable the host firewall.

Stock ansible-lint rules check style/best-practice, not organizational
security policy - this rule closes that specific gap (Question 111).
"""
from ansiblelint.rules import AnsibleLintRule


class NoFirewallDisableRule(AnsibleLintRule):
    id = "no-firewall-disable"
    description = "Tasks must not disable the host firewall (ansible.posix.firewalld state=disabled)"
    severity = "VERY_HIGH"
    tags = ["security", "custom"]

    def matchtask(self, task, file=None):
        module = task.get("action", {}).get("__ansible_module__", "")
        if module in ("ansible.posix.firewalld", "firewalld"):
            return task.get("action", {}).get("state") == "disabled"
        return False
