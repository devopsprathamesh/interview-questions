"""Unit test for the custom no_firewall_disable rule's own matching logic."""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "custom_rules"))
from no_firewall_disable import NoFirewallDisableRule  # noqa: E402


def test_flags_disabled_state():
    rule = NoFirewallDisableRule()
    task = {"action": {"__ansible_module__": "ansible.posix.firewalld", "state": "disabled"}}
    assert rule.matchtask(task) is True


def test_does_not_flag_enabled_state():
    rule = NoFirewallDisableRule()
    task = {"action": {"__ansible_module__": "ansible.posix.firewalld", "state": "enabled"}}
    assert rule.matchtask(task) is False


def test_ignores_unrelated_modules():
    rule = NoFirewallDisableRule()
    task = {"action": {"__ansible_module__": "ansible.builtin.package", "state": "present"}}
    assert rule.matchtask(task) is False
