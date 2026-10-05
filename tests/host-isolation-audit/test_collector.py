"""Offline audit safety checks; never inspect or mutate the real host."""
import argparse
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('collector', REPO / 'scripts/ops/collect-host-isolation-evidence.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class CollectorTests(unittest.TestCase):
    def test_no_confirmation_never_runs_commands(self):
        with patch.object(collector, 'run') as command:
            with self.assertRaises(collector.AuditError):
                collector.require_host(False)
            command.assert_not_called()

    def test_guest_rejected_before_privileged_reads(self):
        with patch.object(collector.os, 'getuid', return_value=1000), \
                patch.object(Path, 'read_text', return_value='ID=ubuntu\n'), \
                patch.object(collector, 'run') as command:
            with self.assertRaises(collector.AuditError):
                collector.require_host(True)
            command.assert_not_called()

    def test_redaction_preserves_order_and_local_rule_semantics(self):
        redactor = collector.Redactor()
        rules = ('-A before -d 224.0.0.251 -p udp --dport 5353 -j ACCEPT\n'
                 '-A input -i virbr1 -s 192.168.231.0/24 -j DROP\n'
                 '-A input -s 8.8.8.8 --comment "private identity" -j DROP\n'
                 '-A input -s 8.8.8.8 -j DROP\n'
                 '2001:4860:4860::8888 aa:bb:cc:dd:ee:ff /home/person/secrets\n')
        result = redactor.text(rules)
        for hidden in ('8.8.8.8', 'private identity', '2001:4860:4860::8888',
                       'aa:bb:cc:dd:ee:ff', '/home/person'):
            self.assertNotIn(hidden, result)
        self.assertEqual(2, result.count('IP4_1'))
        self.assertIn('192.168.231.0/24', result)
        self.assertLess(result.index('5353'), result.index('virbr1'))
        self.assertIn('-j ACCEPT', result)
        self.assertIn('-j DROP', result)

    def test_xml_keeps_host_integration_visible_without_paths(self):
        xml = ('<domain type="kvm"><seclabel type="dynamic" model="apparmor"/>'
               '<devices><filesystem type="mount"><source dir="/home/person"/>'
               '</filesystem><channel type="unix"><source path="/private/socket"/>'
               '</channel></devices></domain>')
        result = collector.xml_summary(xml)
        self.assertIn('filesystem', result)
        self.assertIn('channel', result)
        self.assertIn('apparmor', result)
        self.assertNotIn('/home/person', result)
        self.assertNotIn('/private/socket', result)

    def test_failed_required_capture_cannot_produce_completed_collection(self):
        scratch = REPO / 'tmp/host-audit-tests'
        scratch.mkdir(parents=True, exist_ok=True)
        calls = []

        def fake_run(argv):
            calls.append(argv)
            if 'iptables-save' in argv:
                return 1, '', 'private error detail'
            if 'dumpxml' in argv:
                return 0, '<domain type="kvm"><devices/></domain>', ''
            if 'net-dumpxml' in argv:
                return 0, '<network><bridge name="virbr1"/></network>', ''
            return 0, 'fixture output', ''

        with tempfile.TemporaryDirectory(dir=scratch) as name, \
                patch.object(collector, 'run', side_effect=fake_run), \
                patch.object(collector.shutil, 'which', return_value=None):
            directory = Path(name)
            code = collector.collect(argparse.Namespace(domain='fixture', network='fixture'), directory)
            self.assertEqual(1, code)
            report = (directory / 'candidate-report.md').read_text()
            self.assertIn('INCOMPLETE: iptables-v4', report)
            self.assertNotIn('private error detail', report)
            self.assertIn('private error detail', (directory / 'iptables-v4.txt').read_text())
            self.assertIn('NOT A SECURITY PASS', report)
        for argv in calls:
            self.assertNotIn('ssh', argv)
            self.assertNotIn('docker', argv)
            for forbidden in ('reload', 'restart', 'enable', 'disable', 'apply', 'flush', '-F', '-A', '-I'):
                self.assertNotIn(forbidden, argv)


if __name__ == '__main__':
    unittest.main()
