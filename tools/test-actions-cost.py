import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('cost', Path(__file__).with_name('actions-cost-report.py'))
cost = importlib.util.module_from_spec(spec); spec.loader.exec_module(cost)

class Costs(unittest.TestCase):
    def job(self, **changes):
        return dict(name='native', labels=['macos-26-intel'], runner_name='allocated', started_at='2026-11-07T00:00:00Z', completed_at='2026-11-07T00:00:01Z', conclusion='success', **changes)
    def test_round_each_job_and_count_failed_cancelled_work(self):
        jobs = [self.job(), {**self.job(), 'conclusion': 'failure'}, {**self.job(), 'conclusion': 'cancelled'}]
        self.assertEqual(cost.estimate(jobs)['estimatedUSD'], '0.186')
    def test_no_charge_invented_for_unallocated_skipped_or_running_jobs(self):
        for changes in [{'runner_name': ''}, {'conclusion': 'skipped'}, {'completed_at': None}]:
            self.assertEqual(cost.estimate([{**self.job(), **changes}])['estimatedUSD'], '0')
    def test_unknown_labels_are_unpriced(self):
        self.assertIsNone(cost.estimate([{**self.job(), 'labels': ['self-hosted']}])['jobs'][0]['estimatedUSD'])
        self.assertIsNone(cost.estimate([{**self.job(), 'labels': ['macos-26-large']}])['jobs'][0]['estimatedUSD'])

if __name__ == '__main__': unittest.main()
